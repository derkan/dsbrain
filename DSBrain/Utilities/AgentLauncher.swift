import Foundation
import AppKit

enum AgentLauncher {
    enum LaunchError: LocalizedError {
        case serverStopped
        case missingCLI(AgentKind)
        case invalidPath
        case scriptWriteFailed
        case terminalOpenFailed(String)
        case automationDenied(String)

        var errorDescription: String? {
            switch self {
            case .serverStopped:
                return "Start ds4-server before launching an agent."
            case .missingCLI(let agent):
                return "\(agent.displayName) CLI not found in PATH."
            case .invalidPath:
                return "Selected path is not a directory."
            case .scriptWriteFailed:
                return "Could not write temporary launch script."
            case .terminalOpenFailed(let name):
                return "Could not open \(name). Pick another terminal in Preferences."
            case .automationDenied(let app):
                return "macOS blocked controlling \(app). Enable DSBrain under System Settings → Privacy & Security → Automation, or use Open (no AppleScript) — relaunch DSBrain after changing the toggle."
            }
        }
    }

    /// Launch `agent` with cwd/`path`, using ds4 host/port for Pi/Codex.
    static func launch(
        agent: AgentKind,
        path: String,
        host: String,
        port: Int,
        serverRunning: Bool
    ) throws {
        let normalized = ProjectStore.normalizePath(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDir), isDir.boolValue else {
            throw LaunchError.invalidPath
        }

        switch agent {
        case .cursor:
            try launchCursor(path: normalized)
        case .pi, .codex:
            guard serverRunning else { throw LaunchError.serverStopped }
            let body = try scriptBody(agent: agent, path: normalized, host: host, port: port)
            // `.command` is the macOS convention for “run in Terminal when opened”.
            let scriptURL = try writeLaunchScript(body: body, ext: "command")
            let terminalPath = ConfigManager.shared.load().resolvedTerminalAppPath
            try openScript(scriptURL: scriptURL, terminalAppPath: terminalPath)
        }
    }

    private static func scriptBody(
        agent: AgentKind,
        path: String,
        host: String,
        port: Int
    ) throws -> String {
        let qPath = bashSingleQuote(path)
        // Keep window open on failure so the user can read errors.
        let footer = """
            status=$?
            if [ "$status" -ne 0 ]; then
              echo
              echo "Exit $status — press Return to close."
              read -r _
            fi
            """
        switch agent {
        case .pi:
            return """
            #!/bin/bash
            cd \(qPath) || exit 1
            pi --provider ds4 --model deepseek-v4-flash
            \(footer)
            """
        case .codex:
            let base = "http://\(host):\(port)/v1"
            return """
            #!/bin/bash
            cd \(qPath) || exit 1
            export OPENAI_BASE_URL=\(bashSingleQuote(base))
            export OPENAI_API_KEY=dsv4-local
            codex
            \(footer)
            """
        case .cursor:
            preconditionFailure("cursor uses launchCursor")
        }
    }

    private static func bashSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func writeLaunchScript(body: String, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSBrain-launches", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("launch-\(UUID().uuidString).\(ext)")
        guard let data = body.data(using: .utf8) else { throw LaunchError.scriptWriteFailed }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }

    private static func launchCursor(path: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["cursor", path]
        task.environment = ProcessInfo.processInfo.environment
        do {
            try task.run()
        } catch {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-a", "Cursor", path]
            do {
                try open.run()
            } catch {
                throw LaunchError.missingCLI(.cursor)
            }
        }
    }

    /// Open the launch script with the chosen terminal — no Apple Events required.
    private static func openScript(scriptURL: URL, terminalAppPath: String) throws {
        guard FileManager.default.fileExists(atPath: terminalAppPath) else {
            throw LaunchError.terminalOpenFailed(TerminalApp.displayName(forPath: terminalAppPath))
        }
        let appURL = URL(fileURLWithPath: terminalAppPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // Prefer /usr/bin/open so LaunchServices handles .command like a double-click.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", appURL.path, scriptURL.path]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                // Fallback: NSWorkspace
                NSWorkspace.shared.open(
                    [scriptURL],
                    withApplicationAt: appURL,
                    configuration: config,
                    completionHandler: nil
                )
            }
        } catch {
            NSWorkspace.shared.open(
                [scriptURL],
                withApplicationAt: appURL,
                configuration: config,
                completionHandler: nil
            )
        }
    }
}

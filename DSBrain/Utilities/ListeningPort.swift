import Darwin
import Foundation

struct ListeningProcess: Equatable {
    let pid: pid_t
    let command: String
    let listenAddress: String
    let isDS4Server: Bool

    var displayName: String {
        isDS4Server ? "ds4-server" : command
    }
}

enum ListeningPort {
    static func listeners(on port: Int, host: String = "127.0.0.1") -> [ListeningProcess] {
        guard port > 0, port <= 65535 else { return [] }

        let output = runLsof(arguments: ["-n", "-P", "-iTCP:\(port)", "-sTCP:LISTEN"])
        var seen = Set<pid_t>()
        var results: [ListeningProcess] = []

        for line in output.split(separator: "\n") {
            guard let parsed = parseLine(String(line), port: port) else { continue }
            guard !seen.contains(parsed.pid) else { continue }
            guard addressMatchesHost(parsed.address, configuredHost: host, port: port) else { continue }

            seen.insert(parsed.pid)
            let command = commandLine(for: parsed.pid, lsofCommand: parsed.lsofCommand)
            results.append(ListeningProcess(
                pid: parsed.pid,
                command: command,
                listenAddress: parsed.address,
                isDS4Server: isDS4Server(command: command, lsofCommand: parsed.lsofCommand)
            ))
        }
        return results
    }

    private static func runLsof(arguments: [String]) -> String {
        runCommand(executable: "/usr/sbin/lsof", arguments: arguments, requireSuccess: false) ?? ""
    }

    struct ParsedLine: Equatable {
        let pid: pid_t
        let lsofCommand: String
        let address: String
    }

    /// Parses one `lsof -n -P -iTCP` LISTEN line. Internal for unit tests.
    static func parseLine(_ line: String, port: Int) -> ParsedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("COMMAND") { return nil }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 3, let pid = Int32(parts[1]) else { return nil }

        let portSuffix = ":\(port)"
        guard let address = parts.first(where: {
            $0.hasSuffix(portSuffix) || $0.contains("]\(portSuffix)")
        }) else { return nil }

        return ParsedLine(pid: pid, lsofCommand: parts[0], address: address)
    }

    private static func commandLine(for pid: pid_t, lsofCommand: String) -> String {
        let output = runCommand(
            executable: "/bin/ps",
            arguments: ["-p", String(pid), "-ww", "-o", "args="],
            requireSuccess: false
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !output.isEmpty { return output }

        let comm = runCommand(
            executable: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "comm="],
            requireSuccess: false
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let comm, !comm.isEmpty { return comm }
        return lsofCommand
    }

    private static func isDS4Server(command: String, lsofCommand: String) -> Bool {
        for name in [command, lsofCommand] {
            let lower = name.lowercased()
            if lower.contains("ds4-server") || lower.contains("ds-server") {
                return true
            }
        }
        return false
    }

    private static func addressMatchesHost(_ address: String, configuredHost: String, port: Int) -> Bool {
        let hostPort = address.trimmingCharacters(in: .whitespaces)
        let hostPart: String
        if hostPort.hasPrefix("[") {
            hostPart = String(hostPort.split(separator: "]", maxSplits: 1).first ?? Substring("*"))
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        } else {
            hostPart = hostPort.split(separator: ":", omittingEmptySubsequences: false)
                .dropLast()
                .joined(separator: ":")
        }
        let listenHost = hostPart.isEmpty ? "*" : hostPart

        let configured = configuredHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty || configured == "0.0.0.0" || configured == "*" {
            return true
        }
        if listenHost == "*" || listenHost == "0.0.0.0" || listenHost == configured {
            return true
        }
        if configured == "127.0.0.1", listenHost == "::1" || listenHost == "*" {
            return true
        }
        if configured == "::1", listenHost == "127.0.0.1" || listenHost == "*" {
            return true
        }
        return false
    }

    private static func runCommand(
        executable: String,
        arguments: [String],
        requireSuccess: Bool = true
    ) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if requireSuccess, process.terminationStatus != 0 { return nil }
        return output
    }
}

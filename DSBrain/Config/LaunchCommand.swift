import Foundation

enum LaunchCommand {
    /// Shell used to run the configured command.
    static let shellPath = "/bin/bash"

    /// Multiline is fine — newlines (and optional `\` continuations) are
    /// flattened before `bash -lc`.
    static let defaultCommand = """
        ds4-server
          --model /path/to/ds4/ds4flash.gguf
          --metal
          --ssd-streaming
          --ssd-streaming-cache-experts 24GB
          --ctx 100000
          --tokens 384000
          --kv-disk-dir "$HOME/.cache/ds4-kv"
          --kv-disk-space-mb 8192
          --host 127.0.0.1
          --port 8080
        """

    static let defaultHost = "127.0.0.1"
    static let defaultPort = 8080

    /// Flatten newlines / `\` continuations into one shell line for `bash -lc`.
    static func normalizedForShell(_ command: String) -> String {
        flattenLineBreaks(command)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Preview string for Preferences.
    static func preview(command: String) -> String {
        let cmd = normalizedForShell(command)
        guard !cmd.isEmpty, let cwd = workingDirectory(from: command) else { return cmd }
        return "cd \(ShellQuoting.quote(cwd)) && \(cmd)"
    }

    /// Directory used as process cwd so Metal sources like `metal/flash_attn.metal` resolve.
    /// Absolute first token → its directory; bare name (`ds4-server`) → dirname of `command -v` result.
    /// Relative paths (`./eko.sh`) are not supported.
    static func workingDirectory(from command: String) -> String? {
        guard let raw = tokenize(command).first else { return nil }
        let path = PathExpanding.expandTilde(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if path.hasPrefix("/") {
            return directoryOfBinary((path as NSString).standardizingPath)
        }
        // Relative path with a slash (./foo, bar/baz) — reject.
        if path.contains("/") {
            return nil
        }
        guard let resolved = resolveOnPATH(path) else { return nil }
        return directoryOfBinary(resolved)
    }

    /// Why `workingDirectory` failed, for Start error messages.
    static func workingDirectoryError(for command: String) -> String {
        guard let raw = tokenize(command).first else {
            return "Launch command is empty. Set it in Preferences."
        }
        let path = PathExpanding.expandTilde(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if path.hasPrefix("./") || (path.contains("/") && !path.hasPrefix("/")) {
            return "Launch command must not use a relative path (like \(raw)). Use an absolute path or a PATH name such as ds4-server."
        }
        if !path.contains("/") {
            return "\(raw) was not found in PATH. Install it, or use an absolute path to the binary."
        }
        return "Launch command must start with an absolute path or a PATH name (ds4-server)."
    }

    /// Host from `--host` in the launch command (default `127.0.0.1`).
    static func host(from command: String) -> String {
        flagValue("host", in: command) ?? defaultHost
    }

    /// Port from `--port` in the launch command (default `8080`).
    static func port(from command: String) -> Int {
        guard let raw = flagValue("port", in: command), let value = Int(raw), value > 0, value <= 65535 else {
            return defaultPort
        }
        return value
    }

    /// Value of `--name value` or `--name=value` in a shell-ish command string.
    static func flagValue(_ name: String, in command: String) -> String? {
        let tokens = tokenize(command)
        let flag = "--\(name)"
        let prefix = "\(flag)="
        for i in 0..<tokens.count {
            let token = tokens[i]
            if token == flag {
                guard i + 1 < tokens.count else { return nil }
                return stripQuotes(tokens[i + 1])
            }
            if token.hasPrefix(prefix) {
                return stripQuotes(String(token.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    /// Split on whitespace (including newlines), respecting simple quotes.
    /// Optional shell `\` line continuations are accepted for older configs.
    static func tokenize(_ command: String) -> [String] {
        let flattened = flattenLineBreaks(command)

        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for ch in flattened {
            if let q = quote {
                if ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                continue
            }
            if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Resolve a bare command name via login-shell PATH (`bash -lc 'command -v …'`).
    static func resolveOnPATH(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", "command -v \(ShellQuoting.quote(name))"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard path.hasPrefix("/") else { return nil }
        return path
    }

    /// Turn `\`-continued and bare newlines into spaces (keep other content).
    private static func flattenLineBreaks(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\\r\n", with: " ")
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\\r", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func directoryOfBinary(_ path: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

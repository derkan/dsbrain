import Darwin
import Foundation

/// ds4 singleton lock (`/tmp/ds4.lock` or `DS4_LOCK_FILE`).
/// Acquired before model load / HTTP bind — so a live owner may exist while the port is still free.
enum DS4InstanceLock {
    static let defaultPath = "/tmp/ds4.lock"

    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let raw = environment["DS4_LOCK_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? defaultPath : raw
    }

    /// PID written into the lock file (may be stale if the process already exited).
    static func parseOwnerPID(from contents: String) -> pid_t? {
        let token = contents
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
        guard let value = Int32(token), value > 1 else { return nil }
        return value
    }

    /// Live ds4-server described by the lock file, if the owner PID is still running.
    static func liveOwner(
        lockPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ListeningProcess? {
        let path = lockPath ?? self.path(environment: environment)
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = parseOwnerPID(from: contents)
        else { return nil }
        return ListeningPort.ds4Process(pid: pid)
    }

    /// `ds4: another ds4 process is already running (pid N); refusing to start`
    static func conflictPID(from logLine: String) -> pid_t? {
        let lower = logLine.lowercased()
        guard lower.contains("another ds4 process is already running"),
              lower.contains("refusing to start")
        else { return nil }

        guard let pidRange = logLine.range(of: #"pid\s+(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let matched = logLine[pidRange]
        guard let numRange = matched.range(of: #"\d+"#, options: .regularExpression),
              let value = Int32(matched[numRange]), value > 1
        else { return nil }
        return value
    }
}

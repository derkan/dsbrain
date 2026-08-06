import Foundation

/// Append-only log for fan rule evaluation and SMC writes.
final class FanRulesLogger {
    private let logURL: URL
    private let queue = DispatchQueue(label: "com.derkan.dsbrain.fanruleslogger")

    init(logDir: URL) {
        logURL = logDir.appendingPathComponent("fan-rules.log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    func log(_ message: String) {
        queue.async { [logURL] in
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(stamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    handle.write(data)
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

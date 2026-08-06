import Foundation

final class FileLogger {
    private let logDir: URL
    private let queue = DispatchQueue(label: "com.derkan.dsbrain.filelogger")

    init(logDir: URL) {
        self.logDir = logDir
        createDirectoryIfNeeded()
    }

    func log(_ message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let path = self.todayLogPath()
            do {
                if !FileManager.default.fileExists(atPath: path.path) {
                    try "".write(to: path, atomically: true, encoding: .utf8)
                }
                let handle = try FileHandle(forWritingTo: path)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = message.appending("\n").data(using: .utf8) {
                    handle.write(data)
                }
            } catch {
                print("FileLogger error: \(error)")
            }
        }
    }

    func todayLogPath() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let fileName = "\(formatter.string(from: Date()))-server.log"
        return logDir.appendingPathComponent(fileName)
    }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true, attributes: nil)
    }
}

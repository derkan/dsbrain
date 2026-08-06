import Foundation

/// Tails a log file for an externally started ds4-server (adopted instance).
final class AdoptedLogTailer {
    private var timer: Timer?
    private var fileURL: URL?
    private var offset: UInt64 = 0
    private var onLine: ((String) -> Void)?

    func start(path: String, onLine: @escaping (String) -> Void) {
        stop()
        self.onLine = onLine

        let expanded = PathExpanding.expandTilde(path)
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        fileURL = url
        if let size = fileSize() {
            // Start at end; only new lines appear in the popover ring buffer.
            offset = size
        }

        readNewLines()
        timer = RunLoopTimer.schedule(every: 1.0) { [weak self] _ in
            self?.readNewLines()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fileURL = nil
        onLine = nil
    }

    private func fileSize() -> UInt64? {
        guard let fileURL else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value
    }

    private func readNewLines() {
        guard let fileURL, let onLine else { return }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = size

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        for line in text.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
            onLine(line)
        }
    }
}

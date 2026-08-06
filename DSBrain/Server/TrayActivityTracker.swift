import Foundation

/// Parses ds4-server log lines into coarse activity signals for the tray badge.
struct TrayActivityTracker {
    private(set) var isLoadingModel = false
    private(set) var isRequestBusy = false
    private(set) var prefillPercent: Double?
    private(set) var lastBusyAt: Date?

    private let busyGrace: TimeInterval = 4
    private let logParser = LogParser()
    /// True after at least one `prefill chunk` line in the current prompt.
    private var sawPrefillChunk = false

    mutating func ingest(line: String) {
        let lower = line.lowercased()

        // Do not match SSD "warmup are skipped" — that is not a residency warmup.
        if lower.contains("loading model")
            || lower.contains("load model")
            || lower.contains("loading weights")
            || (lower.contains("warmup") && !lower.contains("skipped"))
        {
            if !lower.contains("failed") {
                isLoadingModel = true
            }
        }

        if lower.contains("listening on http://") {
            isLoadingModel = false
        }

        if lower.contains("prompt start") {
            isRequestBusy = true
            lastBusyAt = Date()
            sawPrefillChunk = false
            // Show bar immediately; chunk lines update the percent.
            if prefillPercent == nil {
                prefillPercent = 0
            }
        }

        if lower.contains("prefill chunk") {
            isRequestBusy = true
            lastBusyAt = Date()
            sawPrefillChunk = true
            if let progress = logParser.extractPrefillProgress(from: line) {
                prefillPercent = progress.percent
            }
        }

        if lower.contains("decoding chunk=") {
            isRequestBusy = true
            lastBusyAt = Date()
            clearPrefillProgress()
        }

        if lower.contains("prompt done")
            || lower.contains("finish=stop")
            || lower.contains("finish=tool_calls")
        {
            isRequestBusy = false
            clearPrefillProgress()
        }

        // Aborted / failed prompts often skip "prompt done".
        if lower.contains("not covered by mapped model views")
            || lower.contains("metal backend unavailable")
            || (lower.contains("abort") && lower.contains("metal"))
        {
            isRequestBusy = false
            clearPrefillProgress()
        }

        if lower.contains("shutdown requested") {
            isLoadingModel = false
            isRequestBusy = false
            clearPrefillProgress()
        }

        if lower.contains("error") && !lower.contains("no error") {
            if lower.contains("failed") || lower.contains("fatal") {
                isLoadingModel = false
            }
        }
    }

    mutating func tick(tokensPerSecond: Double?) {
        if let tps = tokensPerSecond, tps > 0 {
            isRequestBusy = true
            lastBusyAt = Date()
            return
        }
        // Real prefill in progress (saw chunks): keep sticky until prompt done.
        if prefillPercent != nil, sawPrefillChunk {
            isRequestBusy = true
            return
        }
        // prompt start set 0% but no chunks yet — drop after grace (failed/aborted).
        if let lastBusyAt, Date().timeIntervalSince(lastBusyAt) > busyGrace {
            if prefillPercent != nil, !sawPrefillChunk {
                clearPrefillProgress()
            }
            isRequestBusy = false
        }
    }

    mutating func clearPrefillProgress() {
        prefillPercent = nil
        sawPrefillChunk = false
    }

    mutating func resetForStop() {
        isLoadingModel = false
        isRequestBusy = false
        clearPrefillProgress()
        lastBusyAt = nil
    }
}

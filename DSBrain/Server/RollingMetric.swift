import Foundation

/// Rolling window of timestamped samples (live tray rates, not cumulative averages).
struct RollingMetric {
    private(set) var samples: [(at: Date, value: Double)] = []
    var window: TimeInterval

    init(window: TimeInterval = 3) {
        self.window = window
    }

    /// Latest sample still inside the window, after pruning.
    mutating func latest(now: Date = Date()) -> Double? {
        prune(now: now)
        return samples.last?.value
    }

    /// Last recorded value even after the window expires (sticky tray display).
    private(set) var lastValue: Double?

    mutating func record(_ value: Double, at date: Date = Date()) {
        lastValue = value
        samples.append((at: date, value: value))
        prune(now: date)
    }

    mutating func prune(now: Date = Date()) {
        samples.removeAll { now.timeIntervalSince($0.at) > window }
    }

    mutating func reset() {
        samples.removeAll()
        lastValue = nil
    }

    /// Prefer an in-window sample; otherwise the last held value.
    mutating func stickyLatest(now: Date = Date()) -> Double? {
        if let live = latest(now: now) { return live }
        return lastValue
    }

    /// Mean of samples still inside the window.
    mutating func average(now: Date = Date()) -> Double? {
        prune(now: now)
        guard !samples.isEmpty else { return nil }
        return samples.map(\.value).reduce(0, +) / Double(samples.count)
    }
}

import Foundation

enum RunLoopTimer {
    /// Schedules a repeating timer on the main run loop in `.common` mode so it
    /// keeps firing during menu/popover tracking.
    @discardableResult
    static func schedule(
        every interval: TimeInterval,
        tolerance: TimeInterval? = nil,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: block)
        if let tolerance {
            timer.tolerance = tolerance
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

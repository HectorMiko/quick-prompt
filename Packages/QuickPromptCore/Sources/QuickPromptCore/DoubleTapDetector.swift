import Foundation

/// Detects two key presses within `interval` seconds. A third press does not trigger again.
public struct DoubleTapDetector: Sendable {
    public let interval: TimeInterval
    private var lastPress: TimeInterval?

    public init(interval: TimeInterval = 0.2) {
        self.interval = interval
    }

    /// Registers a press at `time` (seconds). Returns `true` when it completes a double press.
    public mutating func registerPress(at time: TimeInterval) -> Bool {
        if let last = lastPress, time - last < interval, time >= last {
            lastPress = nil
            return true
        }
        lastPress = time
        return false
    }
}

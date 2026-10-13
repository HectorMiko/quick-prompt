import Foundation
import Testing
@testable import QuickPromptCore

struct DoubleTapDetectorTests {
    /// Feeds press times to a fresh detector and returns which presses triggered.
    private func triggers(_ times: [TimeInterval]) -> [Bool] {
        var detector = DoubleTapDetector(interval: 0.2)
        return times.map { detector.registerPress(at: $0) }
    }

    @Test func detectsTwoPressesWithinInterval() {
        #expect(triggers([10.0, 10.15]) == [false, true])
    }

    @Test func ignoresSlowPresses() {
        #expect(triggers([10.0, 10.3, 10.4]) == [false, false, true])
    }

    @Test func tripleTapTriggersOnce() {
        #expect(triggers([1.0, 1.1, 1.15]) == [false, true, false])
    }

    @Test func ignoresClockGoingBackwards() {
        #expect(triggers([5.0, 4.9]) == [false, false])
    }
}

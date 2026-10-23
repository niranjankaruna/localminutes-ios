import XCTest

final class HarnessTests: XCTestCase {
    func testHarnessExecutesAnAssertion() {
        // Initial intentional failure is preserved in ef311b9 and its CI run.
        XCTAssertEqual(1 + 1, 2, "T02: the runner executes this assertion")
    }

    func testControlledClockAdvancesWithoutSleeping() {
        var clock = ControlledClock()
        XCTAssertEqual(clock.milliseconds, 0)
        clock.advance(by: 150)
        XCTAssertEqual(clock.milliseconds, 150)
        clock.advance(by: 50)
        XCTAssertEqual(clock.milliseconds, 200)
    }
}

// Deterministic test-only clock; no sleeping or wall-clock dependence.
struct ControlledClock {
    private(set) var milliseconds: UInt64 = 0

    mutating func advance(by amount: UInt64) {
        milliseconds += amount
    }
}

import XCTest

final class HarnessTests: XCTestCase {
    func testHarnessExecutesAnAssertion() {
        // Deliberate RED permitted only for initial harness bootstrap (T02).
        XCTAssertTrue(false, "T02: the runner must execute and report this assertion")
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

// Minimal compiling test-support stub; implement only after hosted RED.
struct ControlledClock {
    private(set) var milliseconds: UInt64 = 0

    mutating func advance(by milliseconds: UInt64) {}
}

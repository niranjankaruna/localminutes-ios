import AppIntents
import XCTest
@testable import LocalMinutes

/// Probe actual SDK defaults before changing the hidden Stop's execution mode.
/// Direct calls do not establish OS delivery or locked-device behavior.
@MainActor
final class RecordingActivityExecutionTests: XCTestCase {
    func testNativeScopedActivityStopDeclaresBackgroundExecution() {
        XCTAssertFalse(StopRecordingActivityIntent.isDiscoverable)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(StopRecordingActivityIntent.supportedModes, .background)
        }
    }
}

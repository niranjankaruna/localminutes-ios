import AppIntents
import XCTest
@testable import LocalMinutes

/// The scoped Stop intent stays hidden and permits background execution.
/// Direct calls do not establish OS delivery or locked-device behavior.
@MainActor
final class RecordingActivityExecutionTests: XCTestCase {
    func testNativeScopedActivityStopDeclaresBackgroundExecution() {
        XCTAssertFalse(StopRecordingActivityIntent.isDiscoverable)
        XCTAssertFalse(StopRecordingActivityIntent.openAppWhenRun)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(StopRecordingActivityIntent.supportedModes, .background)
        }
    }
}

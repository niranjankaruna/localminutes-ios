import AVFoundation
import XCTest
@testable import LocalMinutes

/// Actual AVAudioSession configuration compatibility, without activating the
/// microphone. This does not establish physical background intent delivery.
@MainActor
final class NativeRecordingAudioSessionTests: XCTestCase {
    func testSystemAcceptsMixableMeasurementCaptureConfiguration() throws {
        let session = AVAudioSession.sharedInstance()
        let category = session.category
        let mode = session.mode
        let options = session.categoryOptions
        defer { try? session.setCategory(category, mode: mode, options: options) }

        let hardware = IOSCaptureHardware()
        try hardware.configureSession()
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertEqual(session.mode, .measurement)
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers),
                      "Capture must not request permission to interrupt another app's audio")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
        XCTAssertFalse(session.categoryOptions.contains(.interruptSpokenAudioAndMixWithOthers))
    }
}

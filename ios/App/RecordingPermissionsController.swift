#if os(iOS)
import ActivityKit
import AVFoundation
import Observation

enum RecordingMicrophonePermission: Equatable {
    case notRequested, allowed, denied
}

@MainActor
protocol RecordingPermissionsSource: AnyObject {
    var microphone: RecordingMicrophonePermission { get }
    var liveActivitiesEnabled: Bool { get }
    func requestMicrophone() async
}

@MainActor
private final class SystemRecordingPermissionsSource: RecordingPermissionsSource {
    var microphone: RecordingMicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .notRequested
        case .granted: .allowed
        case .denied: .denied
        @unknown default: .denied
        }
    }

    var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}

/// Permission setup is independent of models, Live Activity creation and audio
/// capture, so a failed recording cannot prevent the system microphone prompt.
@MainActor @Observable
final class RecordingPermissionsController {
    private(set) var microphone: RecordingMicrophonePermission
    private(set) var liveActivitiesEnabled: Bool
    private(set) var requestingMicrophone = false
    @ObservationIgnored private let source: any RecordingPermissionsSource

    convenience init() { self.init(source: SystemRecordingPermissionsSource()) }

    init(source: any RecordingPermissionsSource) {
        self.source = source
        microphone = source.microphone
        liveActivitiesEnabled = source.liveActivitiesEnabled
    }

    func refresh() {
        microphone = source.microphone
        liveActivitiesEnabled = source.liveActivitiesEnabled
    }

    func requestMicrophone() async {
        refresh()
        guard microphone == .notRequested, !requestingMicrophone else { return }
        requestingMicrophone = true
        defer { requestingMicrophone = false }
        await source.requestMicrophone()
        refresh()
    }
}
#endif

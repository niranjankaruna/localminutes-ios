import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

/// A production ready result requires verified installed ASR resources and the
/// real streaming runtime. File presence or a recording-only fallback is not
/// sufficient. Tests may double this preparation boundary, never inference.
public enum RecordingPreparationResult: Sendable, Equatable {
    case ready(directory: URL)
    case rejected(RecordingFailure)
}

@MainActor
public protocol RecordingPreparationSource: AnyObject {
    func prepare(sessionID: UUID) async -> RecordingPreparationResult
}

/// Test-first interface only. The coordinator is real and remains unmodified;
/// no resource preparation, activity, microphone or recording behavior exists.
/// Later implementation composes concrete capture/activity resources here,
/// independently of views, and acknowledges cleanup only after both settle.
@MainActor
public final class RecordingSessionOwner {
    private let coordinator = RecordingCoordinator()

    public var completedManifest: AudioCaptureManifest? { nil }

    public init(
        permission: any CapturePermissionSource,
        hardware: any CaptureHardware,
        activityBackend: any LiveActivityBackend,
        preparation: any RecordingPreparationSource
    ) {}

    public func start(sessionID: UUID) async {}

    public func stop() async {}

    public func toggle(sessionID: UUID) async {}

    public func snapshot() async -> RecordingSnapshot {
        await coordinator.snapshot()
    }
}

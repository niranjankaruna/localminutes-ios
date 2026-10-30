import Foundation

/// Bounded error facts for an explicit recording attempt. Keep the native error
/// identity after teardown without retaining userInfo, paths or meeting content.
public struct CaptureFailureDiagnostic: Sendable, Equatable {
    public enum Stage: String, Sendable, Equatable {
        case sessionActivation = "Activate audio session"
        case inputPreparation = "Prepare microphone input"
        case tapInstallation = "Install microphone tap"
        case engineStart = "Start audio engine"
        case sessionDeactivation = "Deactivate audio session"
    }

    public let sessionID: UUID
    public let stage: Stage
    public let errorDomain: String
    public let errorCode: Int

    public init(sessionID: UUID, stage: Stage, error: any Error) {
        let native = error as NSError
        self.sessionID = sessionID
        self.stage = stage
        errorDomain = String(native.domain.prefix(200))
        errorCode = native.code
    }
}

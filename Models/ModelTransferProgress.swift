import Foundation

public enum ModelTransferStage: String, Equatable, Sendable {
    case preparing, downloading, verifying, installing, completed, paused, failed
}

public struct ModelTransferProgress: Equatable, Sendable {
    public let stage: ModelTransferStage
    public let fileName: String
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let bytesPerSecond: Double?
    public let remainingSeconds: Double?
    public let resumedBytes: Int64
    public var fractionCompleted: Double {
        totalBytes > 0 ? min(1, max(0, Double(completedBytes) / Double(totalBytes))) : 0
    }

    public init(stage: ModelTransferStage, fileName: String, completedBytes: Int64,
                totalBytes: Int64, bytesPerSecond: Double? = nil,
                remainingSeconds: Double? = nil, resumedBytes: Int64 = 0) {
        self.stage = stage; self.fileName = fileName; self.completedBytes = completedBytes
        self.totalBytes = totalBytes; self.bytesPerSecond = bytesPerSecond
        self.remainingSeconds = remainingSeconds; self.resumedBytes = resumedBytes
    }
}

public typealias ModelTransferProgressHandler = @Sendable (ModelTransferProgress) -> Void

extension HTTPSModelTransport {
    // Test-first interface only: no progress behavior until hosted RED is recorded.
    public func downloadResumable(_ artifact: ModelArtifact, to destination: URL,
                                 checkpointDirectory: URL,
                                 progress: @escaping ModelTransferProgressHandler) async throws {
        try await downloadResumable(artifact, to: destination, checkpointDirectory: checkpointDirectory)
    }
}

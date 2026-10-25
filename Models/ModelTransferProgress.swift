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
    public let fileIndex: Int
    public let fileCount: Int
    public let overallCompletedBytes: Int64
    public let overallTotalBytes: Int64
    public var fractionCompleted: Double {
        totalBytes > 0 ? min(1, max(0, Double(completedBytes) / Double(totalBytes))) : 0
    }

    public init(stage: ModelTransferStage, fileName: String, completedBytes: Int64,
                totalBytes: Int64, bytesPerSecond: Double? = nil,
                remainingSeconds: Double? = nil, resumedBytes: Int64 = 0,
                fileIndex: Int = 1, fileCount: Int = 1,
                overallCompletedBytes: Int64? = nil, overallTotalBytes: Int64? = nil) {
        self.stage = stage; self.fileName = fileName; self.completedBytes = completedBytes
        self.totalBytes = totalBytes; self.bytesPerSecond = bytesPerSecond
        self.remainingSeconds = remainingSeconds; self.resumedBytes = resumedBytes
        self.fileIndex = fileIndex; self.fileCount = fileCount
        self.overallCompletedBytes = overallCompletedBytes ?? completedBytes
        self.overallTotalBytes = overallTotalBytes ?? totalBytes
    }
}

public typealias ModelTransferProgressHandler = @Sendable (ModelTransferProgress) -> Void

extension ModelInstallationManager {
    // Test-first aggregate progress interface; behavior awaits hosted RED.
    public func download(_ manifest: ModelManifest,
                         progress: @escaping ModelTransferProgressHandler) async throws -> VerifiedModel {
        try await download(manifest)
    }
}

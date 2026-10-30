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
    public var overallFractionCompleted: Double {
        overallTotalBytes > 0 ? min(1, max(0, Double(overallCompletedBytes) / Double(overallTotalBytes))) : 0
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

final class ModelDownloadProgressReporter: @unchecked Sendable {
    private let manifest: ModelManifest
    private let handler: ModelTransferProgressHandler
    private let total: Int64
    private let offsets: [Int64]
    private let lock = NSLock()
    private var latest: ModelTransferProgress?

    init(manifest: ModelManifest, handler: @escaping ModelTransferProgressHandler) {
        self.manifest = manifest; self.handler = handler
        var sum: Int64 = 0
        var offsets: [Int64] = []
        for artifact in manifest.artifacts { offsets.append(sum); sum += artifact.byteCount }
        self.total = sum; self.offsets = offsets
    }

    func receive(_ value: ModelTransferProgress, index: Int) {
        let asset = manifest.artifacts[index]
        let stage = value.stage == .completed ? ModelTransferStage.verifying : value.stage
        let overall = offsets[index] + (stage == .verifying ? asset.byteCount : value.completedBytes)
        let remaining = value.bytesPerSecond.flatMap { speed -> Double? in
            speed.isFinite && speed > 0 ? Double(max(0, total - overall)) / speed : nil
        }
        emit(.init(stage: stage, fileName: asset.fileName,
            completedBytes: value.completedBytes, totalBytes: asset.byteCount,
            bytesPerSecond: value.bytesPerSecond, remainingSeconds: remaining,
            resumedBytes: value.resumedBytes, fileIndex: index + 1, fileCount: manifest.artifacts.count,
            overallCompletedBytes: overall, overallTotalBytes: total))
    }

    func verifying(index: Int, bytes: Int64) {
        let asset = manifest.artifacts[index]
        emit(.init(stage: .verifying, fileName: asset.fileName,
            completedBytes: bytes, totalBytes: asset.byteCount, fileIndex: index + 1,
            fileCount: manifest.artifacts.count, overallCompletedBytes: total, overallTotalBytes: total))
    }

    func finish(_ stage: ModelTransferStage) {
        let last = lock.withLock { latest }
        let index = stage == .completed || stage == .installing ? manifest.artifacts.count - 1 : max(0, (last?.fileIndex ?? 1) - 1)
        let asset = manifest.artifacts[index]
        let complete = stage == .completed || stage == .installing
        emit(.init(stage: stage, fileName: asset.fileName,
            completedBytes: complete ? asset.byteCount : last?.completedBytes ?? 0,
            totalBytes: asset.byteCount, resumedBytes: last?.resumedBytes ?? 0,
            fileIndex: index + 1, fileCount: manifest.artifacts.count,
            overallCompletedBytes: complete ? total : last?.overallCompletedBytes ?? 0, overallTotalBytes: total))
    }

    private func emit(_ value: ModelTransferProgress) {
        lock.withLock { latest = value }
        handler(value)
    }
}

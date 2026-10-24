import Foundation

public struct SummaryEvidenceSegment: Codable, Equatable, Sendable {
    public let id: String
    public let startSample: Int64
    public let endSample: Int64
    public let text: String

    public init(id: String, startSample: Int64, endSample: Int64, text: String) {
        self.id = id; self.startSample = startSample; self.endSample = endSample; self.text = text
    }
}

public struct SummaryInputChunk: Equatable, Sendable {
    public let segments: [SummaryEvidenceSegment]
    public let prompt: String
    public let promptTokenCount: Int
    public let reservedOutputTokens: Int

    public init(segments: [SummaryEvidenceSegment], prompt: String,
                promptTokenCount: Int, reservedOutputTokens: Int) {
        self.segments = segments; self.prompt = prompt
        self.promptTokenCount = promptTokenCount; self.reservedOutputTokens = reservedOutputTokens
    }
}

public enum SummaryChunkPlannerError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidSource, duplicateSegmentID, invalidTokenCount
    case oversizedSegment(String)
}

/// Counts must include the runtime's complete canonical envelope, not text size.
/// Doubles are permitted in unit tests only; app composition uses the real model.
public typealias SummaryTokenCounter = @Sendable (String) async throws -> Int

/// Atomic source segments retain all sentence text and global sample positions.
/// An oversized segment is an explicit error, never a silently truncated input.
public struct SummaryChunkPlanner: Sendable {
    public let contextTokenLimit: Int
    public let reservedOutputTokens: Int
    public let promptPrefix: String
    private let tokenizer: SummaryTokenCounter

    public init(contextTokenLimit: Int = 4_096, reservedOutputTokens: Int = 512,
                promptPrefix: String, tokenizer: @escaping SummaryTokenCounter) {
        self.contextTokenLimit = contextTokenLimit; self.reservedOutputTokens = reservedOutputTokens
        self.promptPrefix = promptPrefix; self.tokenizer = tokenizer
    }

    public func plan(_ segments: [SummaryEvidenceSegment]) async throws -> [SummaryInputChunk] {
        try Task.checkCancellation()
        return []
    }
}

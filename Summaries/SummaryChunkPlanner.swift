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

/// Whole-source packing is the default. Optional splitting keeps all text bytes
/// and original citation ranges when one source exceeds the model's window.
public struct SummaryChunkPlanner: Sendable {
    public let contextTokenLimit: Int
    public let reservedOutputTokens: Int
    public let promptPrefix: String
    public let maximumSegmentsPerChunk: Int?
    public let splitOversizedSegments: Bool
    private let tokenizer: SummaryTokenCounter
    private let planningProgress: (@Sendable (Int, Int) -> Void)?

    public init(contextTokenLimit: Int = 4_096, reservedOutputTokens: Int = 512,
                promptPrefix: String, maximumSegmentsPerChunk: Int? = nil, splitOversizedSegments: Bool = false,
                planningProgress: (@Sendable (Int, Int) -> Void)? = nil,
                tokenizer: @escaping SummaryTokenCounter) {
        self.contextTokenLimit = contextTokenLimit; self.reservedOutputTokens = reservedOutputTokens
        self.promptPrefix = promptPrefix; self.maximumSegmentsPerChunk = maximumSegmentsPerChunk
        self.splitOversizedSegments = splitOversizedSegments
        self.tokenizer = tokenizer
        self.planningProgress = planningProgress
    }

    public func plan(_ segments: [SummaryEvidenceSegment]) async throws -> [SummaryInputChunk] {
        try Task.checkCancellation()
        guard (64...4_096).contains(contextTokenLimit), (1...1_024).contains(reservedOutputTokens),
              reservedOutputTokens < contextTokenLimit,
              maximumSegmentsPerChunk.map({ (1...256).contains($0) }) ?? true,
              promptPrefix.utf8.count <= 65_536 - Self.evidenceMarker.utf8.count - 2 else {
            throw SummaryChunkPlannerError.invalidConfiguration
        }
        var identities: Set<Data> = []
        var previousEnd: Int64?
        // Validate the complete selected source before building any output.
        planningProgress?(0, segments.count)
        for segment in segments {
            try Task.checkCancellation()
            guard !segment.id.isEmpty, segment.id.utf8.count <= 256,
                  !segment.text.isEmpty, segment.startSample >= 0,
                  segment.endSample >= segment.startSample else {
                throw SummaryChunkPlannerError.invalidSource
            }
            guard identities.insert(Data(segment.id.utf8)).inserted else {
                throw SummaryChunkPlannerError.duplicateSegmentID
            }
            if let previousEnd, segment.startSample < previousEnd {
                throw SummaryChunkPlannerError.invalidSource
            }
            previousEnd = segment.endSample
            guard segment.text.utf8.count <= (splitOversizedSegments ? 1_048_576 : 65_536) else {
                throw SummaryChunkPlannerError.oversizedSegment(segment.id)
            }
        }
        var chunks: [SummaryInputChunk] = []
        var pending: [SummaryEvidenceSegment] = []
        var pendingPrompt = ""
        var pendingTokens = 0
        let progressStride = max(1, segments.count / 100)
        func report(_ completed: Int) {
            if completed == segments.count || completed % progressStride == 0 {
                planningProgress?(completed, segments.count)
            }
        }
        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            if let maximumSegmentsPerChunk, pending.count == maximumSegmentsPerChunk {
                chunks.append(SummaryInputChunk(segments: pending, prompt: pendingPrompt,
                    promptTokenCount: pendingTokens, reservedOutputTokens: reservedOutputTokens))
                pending = []
                pendingPrompt = ""
                pendingTokens = 0
            }
            let candidate = pending + [segment]
            let candidatePrompt = try makePrompt(candidate)
            if let count = try await acceptedTokenCount(candidatePrompt) {
                pending = candidate
                pendingPrompt = candidatePrompt
                pendingTokens = count
                report(index + 1)
                continue
            }
            if !pending.isEmpty {
                chunks.append(SummaryInputChunk(segments: pending, prompt: pendingPrompt,
                    promptTokenCount: pendingTokens, reservedOutputTokens: reservedOutputTokens))
            }
            let singlePrompt = try makePrompt([segment])
            if let count = try await acceptedTokenCount(singlePrompt) {
                pending = [segment]
                pendingPrompt = singlePrompt
                pendingTokens = count
            } else {
                guard splitOversizedSegments else { throw SummaryChunkPlannerError.oversizedSegment(segment.id) }
                let pieces = try await split(segment)
                // Fragments of one source are separate model requests. They
                // retain the original ID and audio range, never invented times.
                chunks += pieces
                pending = []; pendingPrompt = ""; pendingTokens = 0
            }
            report(index + 1)
        }
        if !pending.isEmpty {
            chunks.append(SummaryInputChunk(segments: pending, prompt: pendingPrompt,
                promptTokenCount: pendingTokens, reservedOutputTokens: reservedOutputTokens))
        }
        try Task.checkCancellation()
        return chunks
    }

    private static let evidenceMarker = "\n\nEVIDENCE_JSON:\n"

    private func split(_ segment: SummaryEvidenceSegment) async throws -> [SummaryInputChunk] {
        try Task.checkCancellation()
        let prompt = try makePrompt([segment])
        if let count = try await acceptedTokenCount(prompt) {
            return [.init(segments: [segment], prompt: prompt, promptTokenCount: count,
                          reservedOutputTokens: reservedOutputTokens)]
        }
        let bytes = Data(segment.text.utf8)
        var middle = bytes.count / 2
        while middle > 0, middle < bytes.count, bytes[middle] & 0xC0 == 0x80 { middle -= 1 }
        guard middle > 0, middle < bytes.count else { throw SummaryChunkPlannerError.oversizedSegment(segment.id) }
        let sentence = bytes[..<middle].lastIndex(where: { $0 == 10 || $0 == 13 || $0 == 46 || $0 == 33 || $0 == 63 })
        let word = bytes[..<middle].lastIndex(of: 32)
        if let boundary = [sentence, word].compactMap({ $0 }).first(where: { $0 > middle / 2 }) {
            middle = boundary + 1
        }
        func part(_ data: Data.SubSequence) -> SummaryEvidenceSegment {
            .init(id: segment.id, startSample: segment.startSample, endSample: segment.endSample,
                  text: String(decoding: data, as: UTF8.self))
        }
        let left = try await split(part(bytes[..<middle]))
        let right = try await split(part(bytes[middle...]))
        return left + right
    }

    private func makePrompt(_ segments: [SummaryEvidenceSegment]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let payload = String(data: try encoder.encode(segments), encoding: .utf8) else {
            throw SummaryChunkPlannerError.invalidSource
        }
        return promptPrefix + Self.evidenceMarker + payload
    }

    private func acceptedTokenCount(_ prompt: String) async throws -> Int? {
        try Task.checkCancellation()
        // This is the runtime's input-byte admission limit, not a token estimate.
        // Even a small byte payload still requires actual canonical tokenization.
        guard prompt.utf8.count <= 65_536 else { return nil }
        let count = try await tokenizer(prompt)
        try Task.checkCancellation()
        guard count > 0 else { throw SummaryChunkPlannerError.invalidTokenCount }
        // Subtraction avoids overflow for a malformed tokenizer boundary value.
        return count < contextTokenLimit - reservedOutputTokens ? count : nil
    }
}

import Foundation

public typealias SummaryMapJSONGenerator = @Sendable (String, StructuredJSONSchema, Int) async throws -> String

public enum SummaryPipelinePhase: Equatable, Sendable { case idle, running, completed, failed, cancelled }

public typealias SummaryTokenCounter = @Sendable (String) async throws -> Int

public struct SummaryEvidenceSegment: Codable, Equatable, Sendable {
    public let id: String
    public let startSample: Int64
    public let endSample: Int64
    public let text: String
    public init(id: String, startSample: Int64, endSample: Int64, text: String) {
        self.id = id; self.startSample = startSample; self.endSample = endSample; self.text = text
    }
}


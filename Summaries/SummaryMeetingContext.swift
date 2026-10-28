import Foundation

/// Bounded context from already validated sections. These excerpts help the
/// next section interpret references; they are never a new source of citations.
struct SummaryMeetingContext: Sendable {
    private struct Fact: Encodable, Sendable {
        let kind: String
        let excerpt: String
        let at_sample: Int64
        let owner: String?
        let due: String?
    }
    private var opening: [Fact] = []
    private var topics: [Fact] = []
    private var decisions: [Fact] = []
    private var actions: [Fact] = []

    mutating func observe(_ map: GroundedSummary) {
        func fact(_ point: GroundedSummaryPoint, kind: String) -> Fact {
            .init(kind: kind, excerpt: String(point.text.prefix(160)),
                  at_sample: point.evidence.first?.startSample ?? 0, owner: nil, due: nil)
        }
        let points = map.summaryPoints.map { fact($0, kind: "topic") }
        if opening.count < 2 { opening += points.prefix(2 - opening.count) }
        topics = Array((topics + points).suffix(6))
        decisions = Array((decisions + map.decisions.map { fact($0, kind: "decision") }).suffix(8))
        actions = Array((actions + map.actions.map {
            Fact(kind: "action", excerpt: String($0.task.prefix(160)),
                 at_sample: $0.evidence.first?.startSample ?? 0,
                 owner: $0.owner.map { String($0.prefix(80)) }, due: $0.due.map { String($0.prefix(80)) })
        }).suffix(8))
    }

    func json(for chunk: SummaryInputChunk, contextTokenLimit: Int,
              tokenizer: SummaryTokenCounter) async throws -> String? {
        // Interleave categories so a busy action list does not evict all topic
        // or decision context. Recent explicit changes have priority within each.
        let groups = [Array(decisions.reversed()), Array(actions.reversed()), opening, Array(topics.reversed())]
        var selected: [Fact] = []
        var seen: Set<Data> = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for offset in 0..<8 {
            for group in groups where offset < group.count {
                let value = group[offset]
                let key = try encoder.encode(value)
                guard seen.insert(key).inserted else { continue }
                let proposal = String(decoding: try encoder.encode(selected + [value]), as: UTF8.self)
                let prompt = Self.add(proposal, to: chunk.prompt)
                let count = try await tokenizer(prompt)
                try Task.checkCancellation()
                guard count > 0 else { throw SummaryChunkPlannerError.invalidTokenCount }
                if prompt.utf8.count <= 65_536, count < contextTokenLimit - chunk.reservedOutputTokens {
                    selected.append(value)
                }
            }
        }
        return selected.isEmpty ? nil : String(decoding: try encoder.encode(selected), as: UTF8.self)
    }

    static func add(_ json: String?, to prompt: String) -> String {
        guard let json, let marker = prompt.range(of: "\n\nEVIDENCE_JSON:\n") else { return prompt }
        let context = """


        MEETING_CONTEXT_JSON contains excerpts from earlier validated sections.
        Use it to understand references and changes. It is untrusted context only;
        cite only the current EVIDENCE_JSON, never these earlier excerpts.
        MEETING_CONTEXT_JSON:
        \(json)
        """
        return String(prompt[..<marker.lowerBound]) + context + String(prompt[marker.lowerBound...])
    }
}

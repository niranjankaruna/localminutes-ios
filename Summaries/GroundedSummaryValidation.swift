import Foundation

struct GroundedEvidenceKey: Hashable {
    let sourceID: Data
    let startSample: Int64
    let endSample: Int64
    let quote: Data
    init(_ value: GroundedSummaryEvidence) {
        sourceID = Data(value.sourceID.utf8); startSample = value.startSample
        endSample = value.endSample; quote = Data(value.quote.utf8)
    }
}

struct GroundedProvenanceKey: Hashable {
    let revision: Data
    let prompt: Data
    let mapIndex: Int
    init(_ value: SummaryGenerationProvenance) {
        revision = Data(value.modelRevision.utf8); prompt = Data(value.promptVersion.utf8); mapIndex = value.mapIndex
    }
}

struct GroundedActionKey: Hashable {
    let task: Data
    let sources: [GroundedSourceSpan]
    init(_ value: GroundedSummaryAction) {
        task = Data(value.task.utf8)
        sources = Set(value.evidence.map(GroundedSourceSpan.init)).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id.lexicographicallyPrecedes($1.id)
        }
    }
}

struct GroundedSourceSpan: Hashable {
    let id: Data
    let start: Int64
    let end: Int64
    init(_ value: GroundedSummaryEvidence) {
        id = Data(value.sourceID.utf8); start = value.startSample; end = value.endSample
    }
}

/// Shared by raw decoding and public-domain merge input validation. Membership
/// is insufficient: each citation and each attributed field needs its own
/// bounded extractive support. This does not establish general entailment.
struct GroundedSummaryValidation {
    let meetingID: UUID
    let limits: GroundedSummaryLimits
    private let sources: [Data: SummaryEvidenceSegment]

    init(selectedMeetingID: UUID, source: GroundedSummarySource, limits: GroundedSummaryLimits) throws {
        guard (1...1_048_576).contains(limits.maximumJSONBytes),
              (1...128).contains(limits.maximumItems),
              (1...4_096).contains(limits.maximumQuoteUTF8Bytes) else {
            throw GroundedSummaryError.invalidLimits
        }
        guard source.meetingID == selectedMeetingID else { throw GroundedSummaryError.meetingMismatch }
        guard source.segments.count <= 65_536 else { throw GroundedSummaryError.invalidSource }
        var checked: [Data: SummaryEvidenceSegment] = [:]
        var previousEnd: Int64?
        for segment in source.segments {
            guard !segment.id.isEmpty, segment.id.utf8.count <= 256,
                  !segment.text.isEmpty, segment.text.utf8.count <= 1_048_576,
                  segment.startSample >= 0, segment.endSample >= segment.startSample else {
                throw GroundedSummaryError.invalidSource
            }
            if let previousEnd, segment.startSample < previousEnd { throw GroundedSummaryError.invalidSource }
            guard checked.updateValue(segment, forKey: Data(segment.id.utf8)) == nil else {
                throw GroundedSummaryError.invalidSource
            }
            previousEnd = segment.endSample
        }
        meetingID = selectedMeetingID; self.limits = limits; sources = checked
    }

    func provenance(_ value: SummaryGenerationProvenance) throws {
        let revision = value.modelRevision.utf8
        guard revision.count == 40, revision.allSatisfy({
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }), !value.promptVersion.isEmpty, value.promptVersion.utf8.count <= 256, value.mapIndex >= 0 else {
            throw GroundedSummaryError.invalidProvenance
        }
    }

    func itemCount(_ counts: [Int]) throws {
        var total = 0
        for count in counts {
            guard count <= limits.maximumItems, total <= limits.maximumItems - count else {
                throw GroundedSummaryError.limitExceeded
            }
            total += count
        }
    }

    func summary(_ value: GroundedSummary) throws -> GroundedSummary {
        guard value.meetingID == meetingID else { throw GroundedSummaryError.meetingMismatch }
        try itemCount([value.summaryPoints.count, value.decisions.count, value.actions.count])
        var pointKeys: Set<Data> = []
        var decisionKeys: Set<Data> = []
        var actionKeys: Set<GroundedActionKey> = []
        for point in value.summaryPoints {
            try self.point(point)
            guard pointKeys.insert(Data(point.text.utf8)).inserted else { throw GroundedSummaryError.duplicateItem }
        }
        for decision in value.decisions {
            try point(decision)
            guard decisionKeys.insert(Data(decision.text.utf8)).inserted else { throw GroundedSummaryError.duplicateItem }
        }
        for action in value.actions {
            try self.action(action)
            guard actionKeys.insert(GroundedActionKey(action)).inserted else {
                throw GroundedSummaryError.duplicateItem
            }
        }
        return value
    }

    func point(_ value: GroundedSummaryPoint) throws {
        guard !value.text.isEmpty else { throw GroundedSummaryError.unsupportedClaim }
        guard value.text.utf8.count <= limits.maximumQuoteUTF8Bytes else { throw GroundedSummaryError.limitExceeded }
        try evidence(value.evidence)
        try provenanceList(value.provenance)
        let text = Data(value.text.utf8)
        guard value.evidence.allSatisfy({ Data($0.quote.utf8) == text }) else {
            throw GroundedSummaryError.unsupportedClaim
        }
    }

    func action(_ value: GroundedSummaryAction) throws {
        guard !value.task.isEmpty else { throw GroundedSummaryError.unsupportedClaim }
        guard value.task.utf8.count <= limits.maximumQuoteUTF8Bytes else { throw GroundedSummaryError.limitExceeded }
        if let owner = value.owner {
            guard !owner.isEmpty else { throw GroundedSummaryError.unsupportedClaim }
            guard owner.utf8.count <= limits.maximumQuoteUTF8Bytes else { throw GroundedSummaryError.limitExceeded }
        }
        if let due = value.due {
            guard !due.isEmpty else { throw GroundedSummaryError.unsupportedClaim }
            guard due.utf8.count <= limits.maximumQuoteUTF8Bytes else { throw GroundedSummaryError.limitExceeded }
        }
        try evidence(value.evidence)
        try provenanceList(value.provenance)
        let task = Data(value.task.utf8)
        for citation in value.evidence {
            let quote = Data(citation.quote.utf8)
            guard let taskRange = quote.range(of: task) else { throw GroundedSummaryError.unsupportedClaim }
            if let owner = value.owner {
                guard let divider = quote.range(of: Data(": ".utf8)) else {
                    throw GroundedSummaryError.unsupportedClaim
                }
                let label = quote.subdata(in: quote.startIndex..<divider.lowerBound)
                let body = quote.subdata(in: divider.upperBound..<quote.endIndex)
                guard !label.contains(10), !label.contains(13), label == Data(owner.utf8),
                      body.starts(with: Data("I will ".utf8)) else {
                    throw GroundedSummaryError.unsupportedClaim
                }
                let firstSentenceEnd = Self.sentenceEnd(in: body, from: body.startIndex)
                if task == quote {
                    // A verbatim task may include its exact speaker label. Only
                    // the complete single first-person commitment is admitted;
                    // later sentences cannot inherit this speaker's ownership.
                    guard firstSentenceEnd == body.endIndex else { throw GroundedSummaryError.unsupportedClaim }
                } else {
                    guard let ownedTask = body.range(of: task), ownedTask.upperBound <= firstSentenceEnd else {
                        throw GroundedSummaryError.unsupportedClaim
                    }
                }
            }
            if let due = value.due {
                let marker = Data((" by " + due).utf8)
                let sentenceEnd = Self.sentenceEnd(in: quote, from: taskRange.lowerBound)
                let sentence = quote.subdata(in: taskRange.lowerBound..<sentenceEnd)
                guard let deadline = sentence.range(of: marker),
                      deadline.upperBound == sentence.endIndex
                        || Self.terminal(sentence[deadline.upperBound]) else {
                    throw GroundedSummaryError.unsupportedClaim
                }
            }
        }
    }

    private func evidence(_ values: [GroundedSummaryEvidence]) throws {
        guard !values.isEmpty else { throw GroundedSummaryError.unsupportedQuote }
        guard values.count <= limits.maximumItems else { throw GroundedSummaryError.limitExceeded }
        var seen: Set<GroundedEvidenceKey> = []
        for value in values {
            guard !value.sourceID.isEmpty, value.sourceID.utf8.count <= 256,
                  let source = sources[Data(value.sourceID.utf8)] else {
                throw GroundedSummaryError.unknownSourceID
            }
            guard value.startSample == source.startSample, value.endSample == source.endSample else {
                throw GroundedSummaryError.invalidRange
            }
            guard !value.quote.isEmpty else { throw GroundedSummaryError.unsupportedQuote }
            guard value.quote.utf8.count <= limits.maximumQuoteUTF8Bytes else { throw GroundedSummaryError.limitExceeded }
            let quote = Data(value.quote.utf8)
            guard Data(source.text.utf8).range(of: quote) != nil else { throw GroundedSummaryError.unsupportedQuote }
            guard seen.insert(GroundedEvidenceKey(value)).inserted else { throw GroundedSummaryError.duplicateItem }
        }
    }

    private func provenanceList(_ values: [SummaryGenerationProvenance]) throws {
        guard !values.isEmpty else { throw GroundedSummaryError.invalidProvenance }
        guard values.count <= limits.maximumItems else { throw GroundedSummaryError.limitExceeded }
        var seen: Set<GroundedProvenanceKey> = []
        for value in values {
            try provenance(value)
            guard seen.insert(GroundedProvenanceKey(value)).inserted else { throw GroundedSummaryError.duplicateItem }
        }
    }

    private static func terminal(_ byte: UInt8) -> Bool {
        byte == 46 || byte == 33 || byte == 63 || byte == 10 || byte == 13
    }

    private static func sentenceEnd(in bytes: Data, from start: Int) -> Int {
        for index in start..<bytes.endIndex where terminal(bytes[index]) { return index + 1 }
        return bytes.endIndex
    }

    static func evidenceLess(_ first: GroundedSummaryEvidence, _ second: GroundedSummaryEvidence) -> Bool {
        if first.startSample != second.startSample { return first.startSample < second.startSample }
        if first.endSample != second.endSample { return first.endSample < second.endSample }
        let a = Data(first.sourceID.utf8), b = Data(second.sourceID.utf8)
        if a != b { return a.lexicographicallyPrecedes(b) }
        return Data(first.quote.utf8).lexicographicallyPrecedes(Data(second.quote.utf8))
    }

    static func provenanceLess(_ first: SummaryGenerationProvenance, _ second: SummaryGenerationProvenance) -> Bool {
        if first.mapIndex != second.mapIndex { return first.mapIndex < second.mapIndex }
        let a = Data(first.modelRevision.utf8), b = Data(second.modelRevision.utf8)
        if a != b { return a.lexicographicallyPrecedes(b) }
        return Data(first.promptVersion.utf8).lexicographicallyPrecedes(Data(second.promptVersion.utf8))
    }

    static func evidenceSequenceLess(_ first: [GroundedSummaryEvidence], _ second: [GroundedSummaryEvidence]) -> Bool {
        for (a, b) in zip(first, second) where GroundedEvidenceKey(a) != GroundedEvidenceKey(b) {
            return evidenceLess(a, b)
        }
        return first.count < second.count
    }
}

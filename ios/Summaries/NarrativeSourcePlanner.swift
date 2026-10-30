import Foundation

/// Reconstructs small contiguous reading units across ASR windows. This does
/// not rewrite the transcript, identify speakers, or manufacture word timings.
enum NarrativeSourcePlanner {
    static func units(source: GroundedSummarySource, maximumUnitBytes: Int = 768) throws -> [NarrativeSourceUnit] {
        guard (128...4_096).contains(maximumUnitBytes) else { throw NarrativeSummaryError.invalidConfiguration }
        _ = try SummarySourceValidation(selectedMeetingID: source.meetingID, source: source, limits: .init())
        var result: [NarrativeSourceUnit] = []
        var pending: [SummaryEvidenceSegment] = []
        var pendingBytes = 0
        func flush() {
            guard !pending.isEmpty else { return }
            result.append(.init(id: result.count, segments: pending))
            pending = []; pendingBytes = 0
        }
        for sourceSegment in source.segments {
            try Task.checkCancellation()
            let bytes = Array(sourceSegment.text.utf8)
            var offset = 0
            while offset < bytes.count {
                var end = min(bytes.count, offset + maximumUnitBytes)
                if end < bytes.count {
                    while end > offset, bytes[end] & 0xC0 == 0x80 { end -= 1 }
                    // Prefer a sentence end, then a word boundary, in the latter
                    // half. Every byte is retained, including boundary spaces.
                    let lower = offset + (end - offset) / 2
                    if let boundary = (lower..<end).last(where: { [10, 13, 46, 33, 63].contains(bytes[$0]) }) {
                        end = boundary + 1
                    } else if let boundary = (lower..<end).last(where: { bytes[$0] == 32 }) {
                        end = boundary + 1
                    }
                }
                guard end > offset else { throw NarrativeSummaryError.invalidConfiguration }
                let piece = SummaryEvidenceSegment(id: sourceSegment.id, startSample: sourceSegment.startSample,
                    endSample: sourceSegment.endSample, text: String(decoding: bytes[offset..<end], as: UTF8.self))
                let gap = pending.last.map { sourceSegment.startSample - $0.endSample } ?? 0
                let separator = pending.isEmpty ? 0 : 1
                if !pending.isEmpty && (pendingBytes + separator + end - offset > maximumUnitBytes || gap > 80_000 || pending.count >= 16) {
                    flush()
                }
                pendingBytes += (pending.isEmpty ? 0 : 1) + end - offset
                pending.append(piece)
                offset = end
                // A completed sentence is a preferred boundary once enough
                // neighboring ASR material has been collected for interpretation.
                if pendingBytes >= maximumUnitBytes / 2,
                   let last = piece.text.trimmingCharacters(in: .whitespacesAndNewlines).last,
                   ".!?".contains(last) {
                    flush()
                }
            }
        }
        flush()
        guard result.count <= 65_536 else { throw NarrativeSummaryError.limitExceeded }
        return result
    }
}

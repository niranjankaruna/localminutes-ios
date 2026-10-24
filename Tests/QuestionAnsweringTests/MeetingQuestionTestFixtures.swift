import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesQuestionAnswering

struct QuestionWireOutput: Codable, Sendable {
    let status: String
    let source_id: String
    let quote: String
    func json() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
}

actor QuestionGenerationProbe {
    private(set) var requests: [MeetingQuestionGenerationRequest] = []
    private(set) var outputs: [String] = []
    func record(_ request: MeetingQuestionGenerationRequest, output: String) {
        requests.append(request); outputs.append(output)
    }
}

struct QuestionFixture: Sendable {
    let root: URL
    let database: URL
    let store: SQLiteMeetingStore
    let selected: UUID
    let other: UUID
    let selectedSegments: [StoredTranscriptSegment]
    let otherSegments: [StoredTranscriptSegment]
    let selectedNote: StoredManualNote
    let otherNote: StoredManualNote
}

func questionUUID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

@MainActor
func withQuestionFixture(_ body: (QuestionFixture) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.standardizedFileURL
        .appendingPathComponent("localminutes-qa-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let database = root.appendingPathComponent("meetings.sqlite")
    let store: SQLiteMeetingStore
    do { store = try SQLiteMeetingStore(databaseURL: database) }
    catch { try? FileManager.default.removeItem(at: root); throw error }
    do {
        let selected = questionUUID(1), other = questionUUID(2)
        for id in [selected, other] {
            try await store.createMeeting(MeetingRecord(id: id, title: "Original synthetic meeting \(id)",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed,
                capturedSampleCount: 96_000))
        }
        let selectedSegments = [
            StoredTranscriptSegment(id: questionUUID(10), meetingID: selected, sequence: 0,
                startSample: 16_000, endSample: 32_000,
                text: "Maya: The launch budget is 42000 credits.", modelRevision: "synthetic-asr-revision-A"),
            StoredTranscriptSegment(id: questionUUID(11), meetingID: selected, sequence: 1,
                startSample: 32_000, endSample: 48_000,
                text: "Leo: The training budget is 1800 credits.", modelRevision: "synthetic-asr-revision-A"),
            StoredTranscriptSegment(id: questionUUID(12), meetingID: selected, sequence: 2,
                startSample: 48_000, endSample: 64_000,
                text: "Maya: The launch budget owner remains undecided.", modelRevision: "synthetic-asr-revision-A")
        ]
        let otherSegments = [StoredTranscriptSegment(id: questionUUID(20), meetingID: other, sequence: 0,
            startSample: 0, endSample: 16_000,
            text: "Alex: The launch budget is 999999 credits. Its owner is Alex. OTHER_MEETING_CANARY_7.",
            modelRevision: "synthetic-asr-revision-B")]
        try await store.appendFinalizedSegments(selectedSegments, to: selected)
        try await store.appendFinalizedSegments(otherSegments, to: other)
        let selectedNote = StoredManualNote(meetingID: selected, text: "Original selected notes — do not rewrite.",
            editRevision: 4, modifiedAt: Date(timeIntervalSince1970: 2_000))
        let otherNote = StoredManualNote(meetingID: other, text: "Original other notes — preserve.",
            editRevision: 9, modifiedAt: Date(timeIntervalSince1970: 3_000))
        try await store.saveManualNote(selectedNote); try await store.saveManualNote(otherNote)
        try await body(QuestionFixture(root: root, database: database, store: store,
            selected: selected, other: other, selectedSegments: selectedSegments,
            otherSegments: otherSegments, selectedNote: selectedNote, otherNote: otherNote))
        try await store.close()
        try FileManager.default.removeItem(at: root)
    } catch {
        try? await store.close()
        try? FileManager.default.removeItem(at: root)
        throw error
    }
}

import Foundation
import SQLite3
import XCTest
#if SWIFT_PACKAGE
@testable import LocalMinutesPersistence
#else
@testable import LocalMinutes
#endif

/// Synthetic non-sensitive text; every test gets an actual temporary file URL.
/// No in-memory store, database mock, fixture database or real transcript.
@MainActor
final class SQLiteMeetingStoreTests: XCTestCase {
    func testCreatesAnActualSQLiteDatabaseWithCurrentVersionTwoSchema() async throws {
        try await withDatabase { url in
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.close()
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "Opening the real adapter must create an on-disk database")
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            XCTAssertEqual(try readUserVersion(url), 2, "Version two adds durable original manual notes")
            let handle = try openSQLite(url, flags: SQLITE_OPEN_READONLY)
            defer { sqlite3_close(handle) }
            let tables = try readTextColumn(handle,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('meetings','transcript_segments') ORDER BY name")
            XCTAssertEqual(tables, ["meetings", "transcript_segments"])
        }
    }

    func testMeetingMetadataSurvivesCloseAndReopen() async throws {
        try await withDatabase { url in
            let expected = meetingFixtureRecord(1, title: "Synthetic planning — Café 📝", created: 1_000)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(expected)
            try await store.close()
            await expectError(.closed) { _ = try await store.meeting(id: expected.id) }
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.meeting(id: expected.id)
            XCTAssertEqual(actual, expected)
            try await reopened.close()
        }
    }

    func testHistorySortsNewestFirstWithStableUUIDTieBreakAndLimit() async throws {
        try await withDatabase { url in
            let store = try SQLiteMeetingStore(databaseURL: url)
            let oldest = meetingFixtureRecord(1, created: 100)
            let tiedSecond = meetingFixtureRecord(3, created: 200)
            let tiedFirst = meetingFixtureRecord(2, created: 200)
            for item in [tiedSecond, oldest, tiedFirst] { try await store.createMeeting(item) }
            let history = try await store.history(limit: 2)
            XCTAssertEqual(history.map(\.id), [tiedFirst.id, tiedSecond.id])
            let all = try await store.history()
            XCTAssertEqual(all.map(\.id), [tiedFirst.id, tiedSecond.id, oldest.id])
            await expectError(.invalidInput) { _ = try await store.history(limit: 0) }
            try await store.close()
        }
    }

    func testConcurrentMeetingWritesAndDuplicateIDCannotOverwriteExistingMetadata() async throws {
        try await withDatabase { url in
            let store = try SQLiteMeetingStore(databaseURL: url)
            let original = meetingFixtureRecord(1, title: "Original synthetic title", created: 100)
            try await store.createMeeting(original)
            let concurrent = (2...25).map { meetingFixtureRecord($0, created: TimeInterval($0)) }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in concurrent {
                    group.addTask { try await store.createMeeting(item) }
                }
                try await group.waitForAll()
            }
            await expectError(.meetingConflict) {
                try await store.createMeeting(meetingFixtureRecord(1, title: "Replacement", created: 999))
            }
            let actual = try await store.meeting(id: original.id)
            XCTAssertEqual(actual, original)
            let all = try await store.history()
            XCTAssertEqual(Set(all.map(\.id)), Set(([original] + concurrent).map(\.id)))
            try await store.close()
        }
    }

    func testRenamePersistsLiteralTextWithoutChangingIdentityDateOrTranscript() async throws {
        try await withDatabase { url in
            let store = try SQLiteMeetingStore(databaseURL: url)
            let original = meetingFixtureRecord(1, created: 100)
            let item = segment(10, meetingID: original.id, sequence: 0, text: "Synthetic source")
            try await store.createMeeting(original)
            try await store.appendFinalizedSegments([item], to: original.id)
            let literal = "A title '; DROP TABLE meetings; --"
            try await store.renameMeeting(id: original.id, title: literal)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.meeting(id: original.id)
            XCTAssertEqual(actual, MeetingRecord(id: original.id, title: literal,
                createdAt: original.createdAt, recordingState: original.recordingState,
                capturedSampleCount: original.capturedSampleCount))
            let transcript = try await reopened.transcript(meetingID: original.id)
            XCTAssertEqual(transcript, [item])
            try await reopened.close()
        }
    }

    func testRecordingStateAndCapturedDurationAreDurableAndMissingIDIsAnError() async throws {
        try await withDatabase { url in
            let store = try SQLiteMeetingStore(databaseURL: url)
            let original = meetingFixtureRecord(1, created: 100)
            try await store.createMeeting(original)
            try await store.updateRecordingState(id: original.id, state: .interrupted,
                                                   capturedSampleCount: 1_920_000)
            await expectError(.notFound) {
                try await store.updateRecordingState(id: uuid(999), state: .completed,
                                                     capturedSampleCount: 10)
            }
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.meeting(id: original.id)
            XCTAssertEqual(actual?.recordingState, .interrupted)
            XCTAssertEqual(actual?.capturedSampleCount, 1_920_000)
            XCTAssertEqual(actual?.createdAt, original.createdAt)
            try await reopened.close()
        }
    }

    func testFinalizedTranscriptIsOrderedBySequenceAndSurvivesReopen() async throws {
        try await withDatabase { url in
            let store = try SQLiteMeetingStore(databaseURL: url)
            let meeting = meetingFixtureRecord(1)
            let first = segment(10, meetingID: meeting.id, sequence: 0,
                                start: 0, end: 16_000, text: "First synthetic sentence — Café 📝.")
            let second = segment(11, meetingID: meeting.id, sequence: 1,
                                 start: 16_000, end: 32_000, text: "Second synthetic sentence.")
            try await store.createMeeting(meeting)
            try await store.appendFinalizedSegments([second, first], to: meeting.id)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.transcript(meetingID: meeting.id)
            XCTAssertEqual(actual, [first, second])
            XCTAssertEqual(actual.map(\.modelRevision), ["synthetic-test-revision", "synthetic-test-revision"])
            XCTAssertEqual(actual.first?.startSample, 0)
            XCTAssertEqual(actual.last?.endSample, 32_000)
            try await reopened.close()
        }
    }

    func testReplayingTheSameFinalizedSegmentIsIdempotentAcrossReopen() async throws {
        try await withDatabase { url in
            let meeting = meetingFixtureRecord(1)
            let item = segment(10, meetingID: meeting.id, sequence: 0)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            try await store.appendFinalizedSegments([item, item], to: meeting.id)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            try await reopened.appendFinalizedSegments([item], to: meeting.id)
            let actual = try await reopened.transcript(meetingID: meeting.id)
            XCTAssertEqual(actual, [item], "Replayed durable work must not duplicate finalized text")
            try await reopened.close()
        }
    }

    func testSegmentIDConflictAndSequenceConflictRollbackTheEntireBatch() async throws {
        try await withDatabase { url in
            let meeting = meetingFixtureRecord(1)
            let existing = segment(11, meetingID: meeting.id, sequence: 1, text: "Keep original")
            let first = segment(10, meetingID: meeting.id, sequence: 0)
            let conflictingSequence = segment(12, meetingID: meeting.id, sequence: 1, text: "Conflict")
            let conflictingID = segment(11, meetingID: meeting.id, sequence: 2, text: "Overwrite attempt")
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            try await store.appendFinalizedSegments([existing], to: meeting.id)
            await expectError(.segmentConflict) {
                try await store.appendFinalizedSegments([first, conflictingSequence], to: meeting.id)
            }
            let afterSequenceConflict = try await store.transcript(meetingID: meeting.id)
            XCTAssertEqual(afterSequenceConflict, [existing], "The earlier insert in a failed batch must be rolled back")
            await expectError(.segmentConflict) {
                try await store.appendFinalizedSegments([first, conflictingID], to: meeting.id)
            }
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let afterIDConflict = try await reopened.transcript(meetingID: meeting.id)
            XCTAssertEqual(afterIDConflict, [existing])
            try await reopened.close()
        }
    }

    func testUnknownMeetingAndCrossMeetingSegmentsCannotCreateOrphanRecords() async throws {
        try await withDatabase { url in
            let first = meetingFixtureRecord(1)
            let second = meetingFixtureRecord(2)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(first)
            try await store.createMeeting(second)
            let otherOwnedSegment = segment(10, meetingID: second.id, sequence: 0)
            await expectError(.invalidInput) {
                try await store.appendFinalizedSegments([otherOwnedSegment], to: first.id)
            }
            await expectError(.notFound) {
                try await store.appendFinalizedSegments([segment(11, meetingID: uuid(3), sequence: 0)],
                                                         to: uuid(3))
            }
            let firstTranscript = try await store.transcript(meetingID: first.id)
            let secondTranscript = try await store.transcript(meetingID: second.id)
            XCTAssertEqual(firstTranscript, [])
            XCTAssertEqual(secondTranscript, [])
            let history = try await store.history()
            XCTAssertEqual(Set(history.map(\.id)), Set([first.id, second.id]))
            try await store.close()
        }
    }

    func testSearchIsRestrictedToSelectedMeetingOrderedAndCaseInsensitive() async throws {
        try await withDatabase { url in
            let first = meetingFixtureRecord(1)
            let second = meetingFixtureRecord(2)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(first)
            try await store.createMeeting(second)
            let a = segment(10, meetingID: first.id, sequence: 0, text: "Synthetic ALPHA launch")
            let b = segment(11, meetingID: first.id, sequence: 1, text: "Synthetic alpha review")
            let unrelated = segment(12, meetingID: first.id, sequence: 2, text: "Synthetic beta")
            let privateToSecond = segment(13, meetingID: second.id, sequence: 0, text: "Synthetic alpha other meeting")
            try await store.appendFinalizedSegments([unrelated, b, a], to: first.id)
            try await store.appendFinalizedSegments([privateToSecond], to: second.id)
            let results = try await store.searchTranscript(meetingID: first.id, query: "alpha", limit: 1)
            XCTAssertEqual(results, [a])
            let all = try await store.searchTranscript(meetingID: first.id, query: "ALPHA")
            XCTAssertEqual(all, [a, b])
            XCTAssertFalse(all.contains(where: { $0.meetingID != first.id }))
            try await store.close()
        }
    }

    func testSearchTreatsQuotesAndSQLWildcardsAsLiteralData() async throws {
        try await withDatabase { url in
            let meeting = meetingFixtureRecord(1)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            let literal = segment(10, meetingID: meeting.id, sequence: 0,
                                  text: "Synthetic token %_ and ' OR 1=1 -- retained literally")
            let normal = segment(11, meetingID: meeting.id, sequence: 1, text: "Synthetic ordinary sentence")
            try await store.appendFinalizedSegments([literal, normal], to: meeting.id)
            let injection = try await store.searchTranscript(meetingID: meeting.id, query: "' OR 1=1 --")
            XCTAssertEqual(injection, [literal])
            let wildcard = try await store.searchTranscript(meetingID: meeting.id, query: "%_")
            XCTAssertEqual(wildcard, [literal], "User text must not become SQL LIKE wildcard syntax")
            let empty = try await store.searchTranscript(meetingID: meeting.id, query: "   ")
            XCTAssertEqual(empty, [])
            let surviving = try await store.meeting(id: meeting.id)
            XCTAssertEqual(surviving, meeting)
            try await store.close()
        }
    }

    func testDeletingOneMeetingRemovesOnlyItsMetadataAndTranscript() async throws {
        try await withDatabase { url in
            let sentinel = url.deletingLastPathComponent().appendingPathComponent("unrelated.txt")
            try Data("Synthetic unrelated file".utf8).write(to: sentinel)
            let first = meetingFixtureRecord(1)
            let second = meetingFixtureRecord(2)
            let firstText = segment(10, meetingID: first.id, sequence: 0)
            let secondText = segment(11, meetingID: second.id, sequence: 0)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(first)
            try await store.createMeeting(second)
            try await store.appendFinalizedSegments([firstText], to: first.id)
            try await store.appendFinalizedSegments([secondText], to: second.id)
            try await store.deleteMeeting(id: first.id)
            try await store.deleteMeeting(id: first.id)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let removed = try await reopened.meeting(id: first.id)
            let remaining = try await reopened.meeting(id: second.id)
            let removedTranscript = try await reopened.transcript(meetingID: first.id)
            let remainingTranscript = try await reopened.transcript(meetingID: second.id)
            XCTAssertNil(removed)
            XCTAssertEqual(remaining, second)
            XCTAssertEqual(removedTranscript, [])
            XCTAssertEqual(remainingTranscript, [secondText])
            XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "Synthetic unrelated file")
            try await reopened.close()
        }
    }

    func testInvalidSegmentValuesAreRejectedWithoutPartialWrites() async throws {
        try await withDatabase { url in
            let meeting = meetingFixtureRecord(1)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            let good = segment(10, meetingID: meeting.id, sequence: 0)
            let invalid = [
                segment(11, meetingID: meeting.id, sequence: -1),
                segment(12, meetingID: meeting.id, sequence: 1, start: -1, end: 20),
                segment(13, meetingID: meeting.id, sequence: 1, start: 20, end: 10),
                segment(14, meetingID: meeting.id, sequence: 1, text: " \n "),
                segment(15, meetingID: meeting.id, sequence: 1, modelRevision: "")
            ]
            for bad in invalid {
                await expectError(.invalidInput) {
                    try await store.appendFinalizedSegments([good, bad], to: meeting.id)
                }
                let actual = try await store.transcript(meetingID: meeting.id)
                XCTAssertEqual(actual, [])
            }
            try await store.close()
        }
    }

    func testFutureSchemaIsRejectedWithoutChangingExistingDatabase() async throws {
        try await withDatabase { url in
            let handle = try openSQLite(url, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            let setup = sqlite3_exec(handle,
                "CREATE TABLE future_owner_data(value TEXT); INSERT INTO future_owner_data VALUES ('synthetic sentinel'); PRAGMA user_version=999;",
                nil, nil, nil)
            XCTAssertEqual(setup, SQLITE_OK)
            sqlite3_close(handle)
            XCTAssertThrowsError(try SQLiteMeetingStore(databaseURL: url)) {
                XCTAssertEqual($0 as? MeetingStoreError, .unsupportedSchemaVersion(999))
            }
            XCTAssertEqual(try readUserVersion(url), 999)
            let reopened = try openSQLite(url, flags: SQLITE_OPEN_READONLY)
            defer { sqlite3_close(reopened) }
            XCTAssertEqual(try readTextColumn(reopened, sql: "SELECT value FROM future_owner_data"),
                           ["synthetic sentinel"])
        }
    }
}

// These helpers are confined to tests. Raw SQLite access inspects the actual
// adapter-created file rather than trusting an API that could return hardcoded data.
@MainActor
private func withDatabase(_ body: @MainActor (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalMinutes-SQLiteTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root.appendingPathComponent("meetings.sqlite"))
}

@MainActor
private func expectError(_ expected: MeetingStoreError,
                         file: StaticString = #filePath, line: UInt = #line,
                         operation: @MainActor () async throws -> Void) async {
    do {
        try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? MeetingStoreError, expected, file: file, line: line)
    }
}

private enum SQLiteTestError: Error { case open, prepare, read }

private func openSQLite(_ url: URL, flags: Int32) throws -> OpaquePointer {
    var handle: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &handle, flags, nil)
    guard result == SQLITE_OK, let handle else {
        if let handle { sqlite3_close(handle) }
        throw SQLiteTestError.open
    }
    return handle
}

private func readUserVersion(_ url: URL) throws -> Int32 {
    let handle = try openSQLite(url, flags: SQLITE_OPEN_READONLY)
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
        throw SQLiteTestError.prepare
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw SQLiteTestError.read }
    return sqlite3_column_int(statement, 0)
}

private func readTextColumn(_ handle: OpaquePointer, sql: String) throws -> [String] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
        throw SQLiteTestError.prepare
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while true {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else { throw SQLiteTestError.read }
            values.append(String(cString: text))
        case SQLITE_DONE: return values
        default: throw SQLiteTestError.read
        }
    }
}

private func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
}

private func meetingFixtureRecord(_ suffix: Int, title: String = "Synthetic meeting",
                    created: TimeInterval = 1_000) -> MeetingRecord {
    MeetingRecord(id: uuid(suffix), title: title, createdAt: Date(timeIntervalSince1970: created),
                  recordingState: .recording)
}

private func segment(_ suffix: Int, meetingID: UUID, sequence: Int,
                     start: Int64 = 0, end: Int64 = 16_000,
                     text: String = "Synthetic non-sensitive sentence.",
                     modelRevision: String = "synthetic-test-revision") -> StoredTranscriptSegment {
    StoredTranscriptSegment(id: uuid(suffix), meetingID: meetingID, sequence: sequence,
                            startSample: start, endSample: end, text: text,
                            modelRevision: modelRevision)
}

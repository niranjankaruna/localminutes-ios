import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesMeetingLibrary

/// Real SQLite commits/reads are required. Only their screen projection is held.
@MainActor
final class MeetingSelectionRenameRaceTests: XCTestCase {
    func testOldRenameCannotReplaceAnotherSelectionOrRetargetItsManualNote() async throws {
        try await withRenameRaceStore { store, first, second in
            let gate = RenameReadTestPause()
            let controller = MeetingLibraryController(store: store, afterRenameRead: { id in
                if id == first { await gate.pause() }
            })
            await controller.open(id: first)
            let firstNoteBefore = try await store.manualNote(meetingID: first)
            let rename = Task { await controller.rename("Renamed first meeting") }
            let entered = await waitForRenameRead(gate)
            XCTAssertTrue(entered, "The real rename/read must finish before its stale projection is held")
            guard entered else {
                await gate.release()
                await rename.value
                return
            }
            await controller.open(id: second)
            await controller.search("source")
            let expectedSelection = controller.selected
            let expectedTranscript = controller.transcript
            let expectedNote = controller.note
            let expectedMatches = controller.matches
            XCTAssertEqual(expectedSelection?.id, second)
            XCTAssertEqual(expectedTranscript.map(\.text), ["Synthetic second source"])
            await gate.release()
            await rename.value
            XCTAssertEqual(controller.selected, expectedSelection,
                           "An old read cannot change the meeting selected by a later navigation")
            XCTAssertEqual(controller.transcript, expectedTranscript)
            XCTAssertEqual(controller.note, expectedNote)
            XCTAssertEqual(controller.matches, expectedMatches)
            XCTAssertNil(controller.errorMessage)
            let renamedFirst = try await store.meeting(id: first)
            XCTAssertEqual(renamedFirst?.title, "Renamed first meeting",
                           "Suppressing a stale projection must not undo the committed rename")
            await controller.saveNotes("Synthetic edit belonging to selected second")
            let firstNoteAfter = try await store.manualNote(meetingID: first)
            let secondNoteAfter = try await store.manualNote(meetingID: second)
            XCTAssertEqual(firstNoteAfter, firstNoteBefore,
                           "The stale rename must not retarget B's next notes write into A")
            XCTAssertEqual(secondNoteAfter?.text, "Synthetic edit belonging to selected second")
            XCTAssertEqual(secondNoteAfter?.editRevision, 8)
        }
    }

    func testOldRenameReadCannotOverwriteANewerEpochOfTheSameMeeting() async throws {
        try await withRenameRaceStore { store, first, second in
            let gate = RenameReadTestPause()
            let controller = MeetingLibraryController(store: store, afterRenameRead: { id in
                if id == first { await gate.pause() }
            })
            await controller.open(id: first)
            let rename = Task { await controller.rename("Earlier renamed title") }
            let entered = await waitForRenameRead(gate)
            XCTAssertTrue(entered)
            guard entered else {
                await gate.release()
                await rename.value
                return
            }
            await controller.open(id: second)
            try await store.renameMeeting(id: first, title: "Newest persisted title")
            let newestNote = StoredManualNote(meetingID: first, text: "Newest original first note",
                editRevision: 9, modifiedAt: Date(timeIntervalSince1970: 9_000))
            try await store.saveManualNote(newestNote)
            await controller.open(id: first)
            let expectedSelection = controller.selected
            let expectedTranscript = controller.transcript
            XCTAssertEqual(expectedSelection?.title, "Newest persisted title")
            XCTAssertEqual(controller.note, newestNote)
            await gate.release()
            await rename.value
            XCTAssertEqual(controller.selected, expectedSelection,
                           "Matching UUID alone is insufficient after an A→B→A selection epoch change")
            XCTAssertEqual(controller.transcript, expectedTranscript)
            XCTAssertEqual(controller.note, newestNote)
            XCTAssertNil(controller.errorMessage)
            let durable = try await store.meeting(id: first)
            XCTAssertEqual(durable?.title, "Newest persisted title")
            let exported = try controller.export(markdown: false)
            XCTAssertTrue(exported.contains("Newest persisted title"))
            XCTAssertFalse(exported.contains("Earlier renamed title"))
        }
    }
}

private actor RenameReadTestPause {
    private(set) var entered = false
    private var released = false
    func pause() async {
        entered = true
        let deadline = Date().addingTimeInterval(3)
        while !released && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
    func release() { released = true }
}

private func waitForRenameRead(_ gate: RenameReadTestPause) async -> Bool {
    let deadline = Date().addingTimeInterval(1)
    while Date() < deadline {
        if await gate.entered { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

@MainActor
private func withRenameRaceStore(_ body: @MainActor (SQLiteMeetingStore, UUID, UUID) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("localminutes-rename-race-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
    let first = UUID(), second = UUID()
    for (id, text, revision) in [(first, "Synthetic first source", Int64(4)),
                                 (second, "Synthetic second source", Int64(7))] {
        try await store.createMeeting(MeetingRecord(id: id, title: "Synthetic meeting",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed,
            capturedSampleCount: 16_000))
        try await store.appendFinalizedSegments([StoredTranscriptSegment(id: UUID(), meetingID: id,
            sequence: 0, startSample: 0, endSample: 16_000, text: text,
            modelRevision: "synthetic-fixture-revision")], to: id)
        try await store.saveManualNote(StoredManualNote(meetingID: id,
            text: id == first ? "Synthetic first note" : "Synthetic second note",
            editRevision: revision, modifiedAt: Date(timeIntervalSince1970: 1_000)))
    }
    do { try await body(store, first, second) }
    catch {
        try? await store.close()
        try? FileManager.default.removeItem(at: root)
        throw error
    }
    try await store.close()
    guard root.lastPathComponent.hasPrefix("localminutes-rename-race-tests-"),
          root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        XCTFail("Unsafe fixture cleanup"); return
    }
    try FileManager.default.removeItem(at: root)
}

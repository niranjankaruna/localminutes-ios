#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

@MainActor
final class NativeNotesDraftTests: XCTestCase {
    func testFlushAfterNavigationSavesOnlyTheMeetingBoundToTheEdit() async throws {
        try await withStore { store, alpha, beta in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: alpha)
            let draft = MeetingNotesDraft(controller: controller)
            draft.update("Alpha reviewed notes.")
            await controller.open(id: beta)
            let saved = await draft.flush()
            XCTAssertTrue(saved)
            let first = try await store.manualNote(meetingID: alpha)
            let second = try await store.manualNote(meetingID: beta)
            XCTAssertEqual(first?.text, "Alpha reviewed notes.")
            XCTAssertEqual(second?.text, "Beta original.")
            XCTAssertEqual(controller.selected?.id, beta)
            XCTAssertEqual(controller.note?.text, "Beta original.")
            XCTAssertFalse(draft.hasChanges)
        }
    }

    func testRapidEditsFlushLatestRevisionBeforeTheEditorCanDismiss() async throws {
        try await withStore { store, alpha, _ in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: alpha)
            let draft = MeetingNotesDraft(controller: controller)
            draft.update("First draft.")
            draft.update("Latest draft — café.")
            let saved = await draft.flush()
            XCTAssertTrue(saved)
            let note = try await store.manualNote(meetingID: alpha)
            XCTAssertEqual(note?.text, "Latest draft — café.")
            XCTAssertEqual(note?.editRevision, 2)
            XCTAssertFalse(draft.hasChanges)
            XCTAssertFalse(draft.saving)
            XCTAssertNil(draft.error)
        }
    }

    func testFailedSaveKeepsDraftAndReportsFailureToTheDoneAction() async throws {
        try await withStore { store, alpha, _ in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: alpha)
            let draft = MeetingNotesDraft(controller: controller)
            try await store.close()
            draft.update("Keep this unsaved draft.")
            let saved = await draft.flush()
            XCTAssertFalse(saved)
            XCTAssertTrue(draft.hasChanges)
            XCTAssertEqual(draft.text, "Keep this unsaved draft.")
            XCTAssertNotNil(draft.error)
        }
    }

    private func withStore(_ body: @MainActor (SQLiteMeetingStore, UUID, UUID) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalMinutesNotesDraft-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        let alpha = UUID(), beta = UUID()
        do {
            for (id, text) in [(alpha, "Alpha original."), (beta, "Beta original.")] {
                try await store.createMeeting(.init(id: id, title: text, createdAt: Date(), recordingState: .completed))
                try await store.saveManualNote(.init(meetingID: id, text: text, editRevision: 0, modifiedAt: Date()))
            }
            try await body(store, alpha, beta)
            try? await store.close()
        } catch {
            try? await store.close()
            throw error
        }
    }
}
#endif

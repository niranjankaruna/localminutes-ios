import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesMeetingLibrary

@MainActor
final class HistoryPaginationTests: XCTestCase {
    func testActualSQLiteHistoryLoadsBeyondFirstHundredWithoutDuplicatesOrOrderLoss() async throws {
        try await fixture { f in
            let expected = try await f.store.history(limit: 1_000)
            XCTAssertEqual(expected[99].createdAt, expected[100].createdAt,
                "Exercise the UUID tiebreaker across the actual page boundary")
            let controller = MeetingLibraryController(store: f.store)
            await controller.refresh()
            XCTAssertEqual(controller.meetings, Array(expected.prefix(100)))
            XCTAssertTrue(controller.hasMoreMeetings, "Older stored meetings must remain reachable")
            await controller.loadMoreMeetings()
            XCTAssertEqual(controller.meetings, expected)
            XCTAssertEqual(controller.meetings.count, 103)
            XCTAssertEqual(Set(controller.meetings.map(\.id)).count, 103)
            XCTAssertFalse(controller.hasMoreMeetings)
            await controller.loadMoreMeetings()
            XCTAssertEqual(controller.meetings, expected, "An exhausted page cannot append duplicates")
        }
    }

    func testTitleSearchQueriesOlderSQLiteRowsAndTreatsWildcardAndQuoteCharactersLiterally() async throws {
        try await fixture { f in
            let controller = MeetingLibraryController(store: f.store)
            await controller.refresh()
            XCTAssertFalse(controller.meetings.contains { $0.id == f.oldest.id })
            await controller.searchHistory("100%_ '")
            XCTAssertEqual(controller.meetings.map(\.id), [f.oldest.id],
                "Search must query durable history, not filter the first hundred visible rows")
            XCTAssertFalse(controller.hasMoreMeetings)
            await controller.searchHistory("missing-title-token")
            XCTAssertTrue(controller.meetings.isEmpty)
            await controller.searchHistory("")
            XCTAssertEqual(controller.meetings.count, 100)
            XCTAssertTrue(controller.hasMoreMeetings)
        }
    }

    func testHistoryAndDetailExposeLoadingUntilTheirActualSQLiteReadProjectionSettles() async throws {
        try await fixture { f in
            for operation in [MeetingLibraryReadOperation.history, .detail] {
                let gate = HistoryReadPause()
                let controller = MeetingLibraryController(store: f.store, afterRead: { observed in
                    if observed == operation { await gate.pause() }
                })
                let task = Task {
                    if operation == .history { await controller.refresh() }
                    else { await controller.open(id: f.oldest.id) }
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                while !(await gate.entered), ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(1))
                }
                let entered = await gate.entered
                XCTAssertTrue(entered, "The real SQLite read must finish before its projection is held")
                if entered {
                    XCTAssertEqual(controller.isLoadingHistory, operation == .history)
                    XCTAssertEqual(controller.isLoadingDetail, operation == .detail)
                }
                await gate.release()
                await task.value
                XCTAssertFalse(controller.isLoadingHistory)
                XCTAssertFalse(controller.isLoadingDetail)
                XCTAssertNil(controller.errorMessage)
                if operation == .history { XCTAssertEqual(controller.meetings.count, 100) }
                else { XCTAssertEqual(controller.selected?.id, f.oldest.id) }
            }
        }
    }

    func testClosedSQLiteHistoryAndDetailFailuresClearLoadingAndRetainHonestErrors() async throws {
        try await fixture { f in
            let controller = MeetingLibraryController(store: f.store)
            try await f.store.close()
            await controller.refresh()
            XCTAssertFalse(controller.isLoadingHistory)
            XCTAssertNotNil(controller.errorMessage)
            await controller.open(id: f.oldest.id)
            XCTAssertFalse(controller.isLoadingDetail)
            XCTAssertNotNil(controller.errorMessage)
            XCTAssertNil(controller.selected)
        }
    }

    func testTranscriptSearchLoadsAllFiftyFiveMatchesInOrderWithoutAnotherMeetingsSource() async throws {
        try await fixture { f in
            let matches = (0..<55).map { index in
                StoredTranscriptSegment(id: UUID(), meetingID: f.oldest.id, sequence: index,
                    startSample: Int64(index * 16_000), endSample: Int64((index + 1) * 16_000),
                    text: "Common searchable source \(index)", modelRevision: "synthetic-history-test")
            }
            try await f.store.appendFinalizedSegments(matches, to: f.oldest.id)
            let otherRows = try await f.store.history(limit: 1_000)
            let other = try XCTUnwrap(otherRows.first { $0.id != f.oldest.id })
            try await f.store.appendFinalizedSegments([
                .init(id: UUID(), meetingID: other.id, sequence: 0, startSample: 0, endSample: 16_000,
                    text: "Common searchable other meeting source", modelRevision: "synthetic-history-test")
            ], to: other.id)
            let controller = MeetingLibraryController(store: f.store)
            await controller.open(id: f.oldest.id)
            await controller.search("Common searchable")
            XCTAssertEqual(controller.matches, Array(matches.prefix(50)))
            XCTAssertTrue(controller.hasMoreTranscriptMatches,
                "A bounded first page must keep later matches reachable")
            await controller.loadMoreTranscriptMatches()
            XCTAssertEqual(controller.matches, matches)
            XCTAssertEqual(Set(controller.matches.map(\.id)).count, 55)
            XCTAssertTrue(controller.matches.allSatisfy { $0.meetingID == f.oldest.id })
            XCTAssertFalse(controller.hasMoreTranscriptMatches)
            await controller.loadMoreTranscriptMatches()
            XCTAssertEqual(controller.matches, matches)
            await controller.search("source 54")
            XCTAssertEqual(controller.matches, [matches[54]])
            XCTAssertFalse(controller.hasMoreTranscriptMatches)
            await controller.search("")
            XCTAssertTrue(controller.matches.isEmpty)
            XCTAssertFalse(controller.hasMoreTranscriptMatches)
        }
    }

    private func fixture(_ body: (HistoryPaginationFixture) async throws -> Void) async throws {
        let f = try HistoryPaginationFixture()
        try await f.seed()
        do { try await body(f) }
        catch { try? await f.store.close(); try? f.remove(); throw error }
        try await f.store.close()
        try f.remove()
    }
}

private actor HistoryReadPause {
    private(set) var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        if !released { await withCheckedContinuation { waiter = $0 } }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}

private struct HistoryPaginationFixture {
    let parent: URL
    let root: URL
    let store: SQLiteMeetingStore
    let oldest = MeetingRecord(id: UUID(), title: "Oldest 100%_ ' literal meeting",
        createdAt: Date(timeIntervalSince1970: 0), recordingState: .completed)
    init() throws {
        parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        root = parent.appendingPathComponent("localminutes-history-page-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
    }
    func seed() async throws {
        try await store.createMeeting(oldest)
        for index in 1...102 {
            try await store.createMeeting(.init(id: UUID(), title: "Stored meeting \(index)",
                createdAt: Date(timeIntervalSince1970: Double(1 + index / 4)), recordingState: .completed))
        }
    }
    func remove() throws {
        guard root.deletingLastPathComponent() == parent,
              root.lastPathComponent.hasPrefix("localminutes-history-page-"),
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse history fixture cleanup outside its owned root"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}

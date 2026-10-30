import Foundation
import XCTest
@testable import LocalMinutesPersistence

@MainActor
final class UnfinishedMeetingPaginationTests: XCTestCase {
    func testUnfinishedMeetingsUseExclusiveUUIDKeysetsAndExcludeCompletedFromEveryPage() async throws {
        try await withUnfinishedStore { store in
            let states: [Int: MeetingRecordingState] = [1: .recording, 2: .failed,
                3: .completed, 4: .interrupted, 5: .recovered, 6: .completed]
            for number in [5, 2, 6, 4, 1, 3] {
                try await store.createMeeting(MeetingRecord(id: unfinishedUUID(number),
                    title: "Synthetic pagination meeting", createdAt: Date(timeIntervalSince1970: Double(number)),
                    recordingState: states[number]!))
            }
            let first = try await store.unfinishedMeetings(afterID: nil, limit: 2)
            let second = try await store.unfinishedMeetings(afterID: unfinishedUUID(2), limit: 2)
            let last = try await store.unfinishedMeetings(afterID: unfinishedUUID(5), limit: 2)
            XCTAssertEqual(first.map(\.id), [unfinishedUUID(1), unfinishedUUID(2)])
            XCTAssertEqual(second.map(\.id), [unfinishedUUID(4), unfinishedUUID(5)])
            XCTAssertTrue(last.isEmpty)
            let afterCompletedKey = try await store.unfinishedMeetings(afterID: unfinishedUUID(3), limit: 2)
            XCTAssertEqual(afterCompletedKey.map(\.id), [unfinishedUUID(4), unfinishedUUID(5)],
                           "The exclusive key need not identify an unfinished row")
            let all = try await store.unfinishedMeetings(afterID: nil)
            XCTAssertEqual(all.map(\.id), [1, 2, 4, 5].map(unfinishedUUID))
            XCTAssertTrue(all.allSatisfy { $0.recordingState != .completed })
            let untouched = try await store.meeting(id: unfinishedUUID(3))
            XCTAssertEqual(untouched?.recordingState, .completed)
        }
    }

    func testUnfinishedPaginationDefaultsToOneHundredValidatesBoundsAndReportsAClosedActualDatabase() async throws {
        try await withUnfinishedStore { store in
            for number in 1...101 {
                try await store.createMeeting(MeetingRecord(id: unfinishedUUID(number),
                    title: "Synthetic paged meeting", createdAt: Date(timeIntervalSince1970: 1_000),
                    recordingState: .recording))
            }
            let defaultPage = try await store.unfinishedMeetings(afterID: nil)
            XCTAssertEqual(defaultPage.count, 100)
            XCTAssertEqual(defaultPage.last?.id, unfinishedUUID(100))
            let allowedMaximum = try await store.unfinishedMeetings(afterID: nil, limit: 1_000)
            XCTAssertEqual(allowedMaximum.count, 101)
            let remainder = try await store.unfinishedMeetings(afterID: unfinishedUUID(100), limit: 1_000)
            XCTAssertEqual(remainder.map(\.id), [unfinishedUUID(101)])
            for invalid in [-1, 0, 1_001, Int.max] {
                do {
                    _ = try await store.unfinishedMeetings(afterID: nil, limit: invalid)
                    XCTFail("An invalid page size must not be silently clamped or accepted")
                } catch { XCTAssertEqual(error as? MeetingStoreError, .invalidInput) }
            }
            try await store.close()
            do {
                _ = try await store.unfinishedMeetings(afterID: nil)
                XCTFail("A closed real database must not masquerade as an empty library")
            } catch { XCTAssertEqual(error as? MeetingStoreError, .closed) }
        }
    }
}

@MainActor
private func withUnfinishedStore(_ body: @MainActor (SQLiteMeetingStore) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("localminutes-unfinished-page-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
    do { try await body(store) }
    catch { try? await store.close(); try? FileManager.default.removeItem(at: root); throw error }
    try? await store.close()
    guard root.lastPathComponent.hasPrefix("localminutes-unfinished-page-tests-"),
          root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        XCTFail("Unsafe fixture cleanup"); return
    }
    try FileManager.default.removeItem(at: root)
}

private func unfinishedUUID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

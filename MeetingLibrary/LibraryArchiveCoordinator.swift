import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesPersistence
#endif

public struct ActiveLibrarySelection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generationID: UUID
    public init(schemaVersion: Int = 1, generationID: UUID) {
        self.schemaVersion = schemaVersion; self.generationID = generationID
    }
}

public enum LibraryArchiveCoordinatorError: Error, Equatable, Sendable {
    case notImplemented, busy, invalidActivePointer, invalidBackup, metadataFailure, filesystemFailure
}

/// TEST-FIRST integration boundary only. Models/ModelSelections/Diagnostics stay
/// at applicationRoot; only meetings.sqlite and Meetings belong to a generation.
@MainActor
public final class LibraryArchiveCoordinator {
    public init(applicationRoot: URL, currentLibraryRoot: URL, store: SQLiteMeetingStore,
                usage: MeetingUsageRegistry, admission: HeavyModelAdmission,
                canMaintain: @escaping @MainActor () -> Bool) {}

    // Scheduling only; never a fake snapshot, archive, database or inference.
    init(applicationRoot: URL, currentLibraryRoot: URL, store: SQLiteMeetingStore,
         usage: MeetingUsageRegistry, admission: HeavyModelAdmission,
         canMaintain: @escaping @MainActor () -> Bool,
         afterMaintenance: @escaping @Sendable () async -> Void) {}

    public func export(to archiveURL: URL) async throws -> MeetingArchiveManifest {
        throw LibraryArchiveCoordinatorError.notImplemented
    }
    public func restore(from archiveURL: URL) async throws -> URL {
        throw LibraryArchiveCoordinatorError.notImplemented
    }
    public static func activeLibraryRoot(at applicationRoot: URL) throws -> URL { applicationRoot }
}

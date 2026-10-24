#if os(iOS)
import Foundation

extension RecordingApplication {
    func exportLibraryBackup() async throws -> URL {
        guard let services else { throw LibraryArchiveCoordinatorError.busy }
        try setLibraryRestoreActive(true)
        defer { try? setLibraryRestoreActive(false) }
        return try await services.exportBackup()
    }

    func restoreLibrary(from archiveURL: URL) async throws {
        try Task.checkCancellation()
        guard !isRestoringLibrary, let old = services else { throw LibraryArchiveCoordinatorError.busy }
        if let state = await owner?.snapshot(), state.cleanupPending || state.readiness.audioSessionActive
            || [.preparing, .recording, .stopping].contains(state.phase) {
            throw LibraryArchiveCoordinatorError.busy
        }
        guard playbackOwnership?.hasPlaybackOwnership != true else { throw LibraryArchiveCoordinatorError.busy }
        await old.initialize()
        try old.beginLibraryMaintenance()
        do { try setLibraryRestoreActive(true) }
        catch { old.endLibraryMaintenance(); throw error }
        defer { old.endLibraryMaintenance(); try? setLibraryRestoreActive(false) }
        let pointer = old.applicationRoot.appendingPathComponent("activeLibrary.json")
        let previous: Data?
        if FileManager.default.fileExists(atPath: pointer.path) {
            try PersistentFilePolicy.validateItem(pointer, within: old.applicationRoot)
            let size = try pointer.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 4_096 else { throw LibraryArchiveCoordinatorError.invalidActivePointer }
            previous = try Data(contentsOf: pointer)
        } else { previous = nil }
        var published = false
        do {
            _ = try await old.archives.restore(from: archiveURL)
            published = true
            let replacement = try LocalMinutesServices(rootURL: old.applicationRoot)
            await replacement.initialize()
            guard replacement.startup.state == .ready else {
                try? await replacement.store.close()
                throw LibraryArchiveCoordinatorError.metadataFailure
            }
            activateLibraryServices(replacement)
        } catch {
            if published {
                if let previous {
                    try PersistentFilePolicy.writeAtomically(previous, to: pointer, within: old.applicationRoot)
                } else {
                    try PersistentFilePolicy.validateItem(pointer, within: old.applicationRoot)
                    try FileManager.default.removeItem(at: pointer)
                }
            }
            // The coordinator may have closed its source before a filesystem
            // publication failure. Reopen the retained previous library then.
            do { _ = try await old.store.history() }
            catch {
                let reopened = try LocalMinutesServices(rootURL: old.applicationRoot)
                await reopened.initialize()
                guard reopened.startup.state == .ready else { throw LibraryArchiveCoordinatorError.metadataFailure }
                activateLibraryServices(reopened)
            }
            throw error
        }
    }
}
#endif

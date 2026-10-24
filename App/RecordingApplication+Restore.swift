#if os(iOS)
import Foundation

extension RecordingApplication {
    /// TEST-FIRST user-confirmed restore entry. Real application rebinding must
    /// follow native assertion RED and retain the old library on any failure.
    func restoreLibrary(from archiveURL: URL) async throws {
        throw LibraryArchiveCoordinatorError.notImplemented
    }
}
#endif

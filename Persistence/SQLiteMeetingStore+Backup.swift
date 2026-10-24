import Foundation

public enum SQLiteSnapshotError: Error, Equatable, Sendable {
    case notImplemented, invalidDestination, destinationExists, unsafeDestination, databaseFailure
}

/// Snapshot contract for SQLiteMeetingStore.createSnapshot(at:):
/// - use SQLite's native consistent backup boundary, including committed WAL;
/// - publish one closed standalone database to a fresh, symlink-free path;
/// - preserve originals, source WAL and unrelated sibling files;
/// - honor cancellation before publication and clean only owned staging;
/// - perform no upload, schema migration, audio/model copying or app-root swap.
/// App-wide recording/playback admission and the later CAF archive composition
/// remain separate requirements. The actor API is currently a test-first stub
/// in SQLiteMeetingStore.swift so its private connection never escapes.

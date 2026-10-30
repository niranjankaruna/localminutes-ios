import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import LocalMinutesModels

/// Real disk writes, installer hashing and publication on Darwin. Synthetic
/// bytes are not inference weights and are never passed to a native engine.
final class LargeModelTransferTests: XCTestCase {
    func testLargeDownloadVerificationAndReopenKeepPeakMemoryIndependentOfFileSize() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = parent.appendingPathComponent("localminutes-large-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.bin")
        let byteCount = 512 * 1_024 * 1_024
        let digest = try makeSyntheticFile(source, byteCount: byteCount)
        let revision = String(repeating: "a", count: 40)
        let artifact = ModelArtifact(role: .summary, fileName: "fixture.gguf", byteCount: Int64(byteCount),
            sha256: digest, downloadURL: URL(string: "https://huggingface.co/example/large-file/resolve/\(revision)/fixture.gguf")!,
            digestProvenance: .independentlyDownloaded)
        let manifest = ModelManifest(modelID: "large-transfer-fixture", purpose: .summary,
            upstreamRepository: URL(string: "https://huggingface.co/example/large-file")!, revision: revision,
            licenseIdentifier: "MIT", licenseNotice: "Synthetic repeated bytes, not a model.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [artifact])
        let manager = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
            availableBytes: { _ in 32_000_000_000 }, downloader: { _, output in
                try FileManager.default.copyItem(at: source, to: output)
            })
        let before = try peakResidentBytes()
        let installed = try await manager.download(manifest)
        let reopened = try await manager.current(modelID: manifest.modelID)
        let after = try peakResidentBytes()
        XCTAssertEqual(installed.manifest, reopened?.manifest)
        XCTAssertEqual(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, byteCount)
        print("LARGE_TRANSFER_MEMORY file_bytes=\(byteCount) peak_before=\(before) peak_after=\(after) growth=\(after - before)")
        XCTAssertLessThan(after - before, 64 * 1_024 * 1_024,
            "A 512 MiB file must not retain file-sized temporary buffers during checksum verification or reopen")
    }

    private func peakResidentBytes() throws -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw CocoaError(.fileReadUnknown) }
        return Int64(usage.ru_maxrss) // Darwin reports bytes, unlike Linux.
    }

    private func makeSyntheticFile(_ url: URL, byteCount: Int) throws -> String {
        let descriptor = url.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600)) }
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        let block = Data(repeating: 0x5a, count: 65_536)
        var digest = SHA256()
        for _ in 0..<(byteCount / block.count) {
            try block.withUnsafeBytes { bytes in
                var written = 0
                while written < bytes.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                    guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                    written += count
                }
            }
            digest.update(data: block)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

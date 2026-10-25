import CryptoKit
import Foundation
import XCTest
import LocalMinutesModels
@testable import LocalMinutesTranscription

@MainActor
final class ParakeetModelPackNativeTests: XCTestCase {
    func testActualV3PackUsesItsOwnPinAndDecodesLicensedSpeechOnCPU() async throws {
        let fixture = try ParakeetV3Fixture.load()
        let recognizer = CoreMLParakeetRecognizer(files: .init(directory: fixture.directory, manifest: fixture.manifest))
        do {
            try await recognizer.load()
            let loaded = await recognizer.snapshot()
            XCTAssertEqual(loaded.modelRevision, fixture.manifest.revision)
            XCTAssertEqual(loaded.computePolicy, .cpuOnly)
            try await recognizer.start(epochID: UUID())
            var text = ""
            for offset in stride(from: 0, to: fixture.samples.count, by: CoreMLParakeetRecognizer.stepSamples) {
                let update = try await recognizer.accept(Array(fixture.samples[offset..<min(offset + CoreMLParakeetRecognizer.stepSamples, fixture.samples.count)]),
                    at: Int64(offset))
                text += update.finalized.map(\.text).joined(separator: " ")
            }
            let final = try await recognizer.finish()
            text += final.finalized.map(\.text).joined(separator: " ")
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "The actual v3 engine must emit text for licensed speech; no quality score is imposed")
            await recognizer.unload()
        } catch {
            await recognizer.unload()
            XCTFail("The verified v3 pack must load through its own supported TDT contract: \(error)")
        }
    }
}

struct ParakeetV3Fixture {
    let directory: URL
    let manifest: ModelManifest
    let samples: [Float]

    @MainActor static func load() throws -> Self {
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_PARAKEET_V3_DIRECTORY"]), isDirectory: true)
        let pack = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_PARAKEET_V3_PACK"]))
        let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: pack))
        XCTAssertEqual(manifest.parakeetConfiguration?.decoderContract, "parakeet-tdt-v3")
        for artifact in manifest.artifacts {
            let url = directory.appendingPathComponent(artifact.fileName)
            XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int(artifact.byteCount))
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            var hash = SHA256()
            try ModelFileIO.forEachChunk(in: input) { hash.update(data: $0) }
            XCTAssertEqual(hash.finalize().map { String(format: "%02x", $0) }.joined(), artifact.sha256)
        }
        let speech = try CoreMLParakeetFixture.load()
        return .init(directory: directory, manifest: manifest, samples: speech.samples)
    }
}

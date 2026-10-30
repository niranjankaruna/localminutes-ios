import Foundation
import XCTest
@testable import LocalMinutesModels

final class ModelDeviceResourceReaderTests: XCTestCase {
    func testResourceReaderReportsActualOwnedVolumeAndPhysicalRAMOnTheHost() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let directory = parent.appendingPathComponent("LocalMinutesResourceFacts-\(UUID().uuidString)",
                                                     isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            if directory.deletingLastPathComponent().standardizedFileURL == parent,
               directory.lastPathComponent.hasPrefix("LocalMinutesResourceFacts-"),
               directory.resolvingSymlinksInPath().standardizedFileURL == directory {
                try? FileManager.default.removeItem(at: directory)
            } else { XCTFail("Refuse cleanup outside the owned resource fixture") }
        }
        let physicalRAM = Int64(clamping: ProcessInfo.processInfo.physicalMemory)
        XCTAssertGreaterThan(physicalRAM, 0, "Host RAM must be available independently of the adapter")
        let values = try directory.resourceValues(forKeys: [.volumeTotalCapacityKey])
        let total = try XCTUnwrap(values.volumeTotalCapacity, "Volume metadata is a setup prerequisite")
        XCTAssertGreaterThan(total, 0)
        let observed = ModelDeviceResourcesReader.current(at: directory)
        XCTAssertEqual(observed.totalMemoryBytes, physicalRAM)
        let free = try XCTUnwrap(observed.freeDiskBytes, "Measure the existing owned volume")
        XCTAssertGreaterThan(free, 0)
        XCTAssertLessThanOrEqual(free, Int64(total))
        // No comparison of desktop RAM with a physical iPhone admission budget.
    }

    func testNonFileURLKeepsStorageUnknownWhilePhysicalRAMRemainsActual() {
        let observed = ModelDeviceResourcesReader.current(
            at: URL(string: "https://huggingface.co/example/model")!)
        XCTAssertNil(observed.freeDiskBytes)
        XCTAssertEqual(observed.totalMemoryBytes, Int64(clamping: ProcessInfo.processInfo.physicalMemory))
    }
}

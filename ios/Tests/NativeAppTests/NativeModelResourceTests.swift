#if os(iOS)
import Foundation
import os
import XCTest
@testable import LocalMinutes

@MainActor
final class NativeModelResourceTests: XCTestCase {
    func testModelResourcesReadActualVolumeAndPhysicalRAMWithoutFabricatedCapacity() throws {
        let storage = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let facts = ModelDeviceResourcesReader.current(at: storage)
        XCTAssertEqual(facts.totalMemoryBytes, Int64(clamping: ProcessInfo.processInfo.physicalMemory))
        let free = try XCTUnwrap(facts.freeDiskBytes, "The current owned volume must be measured")
        XCTAssertGreaterThan(free, 0)
        let values = try storage.resourceValues(forKeys: [.volumeTotalCapacityKey])
        let total = try XCTUnwrap(values.volumeTotalCapacity)
        XCTAssertLessThanOrEqual(free, Int64(total))
        // The advisory app budget is different from total physical RAM. A
        // Simulator may not supply one; zero must be represented as unknown.
        let observed = os_proc_available_memory()
        if observed > 0 {
            let available = try XCTUnwrap(facts.availableAppMemoryBytes)
            XCTAssertGreaterThan(available, 0)
            let next = Int64(clamping: observed)
            let difference = available >= next ? available - next : next - available
            XCTAssertLessThanOrEqual(difference, 512 * 1_024 * 1_024,
                "The advisory budget must come from a fresh OS query, allowing intervening allocations")
        } else { XCTAssertNil(facts.availableAppMemoryBytes) }
    }

    func testModelResourcesDoNotInventFreeStorageForAnUnusablePath() {
        let facts = ModelDeviceResourcesReader.current(at: URL(string: "https://huggingface.co/example/model")!)
        XCTAssertNil(facts.freeDiskBytes)
        XCTAssertEqual(facts.totalMemoryBytes, Int64(clamping: ProcessInfo.processInfo.physicalMemory))
    }
}
#endif

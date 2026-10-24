import Foundation
#if os(iOS) || os(tvOS)
import os
#endif

public enum ModelDeviceResourcesReader {
    // Advisory current facts, never cached as a future allocation guarantee.
    public static func current(at storageDirectory: URL) -> DeviceModelResources {
        let physical = Int64(clamping: ProcessInfo.processInfo.physicalMemory)
        var disk: Int64?
        if storageDirectory.isFileURL,
           let values = try? storageDirectory.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            let measured = values.volumeAvailableCapacityForImportantUsage
                ?? values.volumeAvailableCapacity.map(Int64.init)
            disk = measured.flatMap { $0 >= 0 ? $0 : nil }
        }
        let available: Int64?
        #if os(iOS) || os(tvOS)
        let reported = os_proc_available_memory()
        available = reported > 0 ? Int64(clamping: reported) : nil
        #else
        // Desktop host facts do not measure an iPhone's app-specific limit.
        available = nil
        #endif
        return .init(freeDiskBytes: disk, totalMemoryBytes: physical > 0 ? physical : nil,
                     availableAppMemoryBytes: available)
    }
}

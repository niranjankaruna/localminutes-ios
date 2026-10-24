#if os(iOS)
import Foundation

enum ModelDeviceResourcesReader {
    // Test-first adapter seam. The real device facts await hosted assertion RED.
    static func current(at storageDirectory: URL) -> DeviceModelResources {
        .init(freeDiskBytes: nil, totalMemoryBytes: nil, availableAppMemoryBytes: nil)
    }
}
#endif

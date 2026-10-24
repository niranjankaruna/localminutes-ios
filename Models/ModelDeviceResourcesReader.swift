import Foundation

public enum ModelDeviceResourcesReader {
    // Test-first adapter seam. Real platform facts await hosted assertion RED.
    // macOS volume/RAM facts do not establish iPhone app-memory availability.
    public static func current(at storageDirectory: URL) -> DeviceModelResources {
        .init(freeDiskBytes: nil, totalMemoryBytes: nil, availableAppMemoryBytes: nil)
    }
}

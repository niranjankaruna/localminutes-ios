# Minimal no-behavior activation seams

Inactive only. No active source, tests, workflow or state may change from this
draft. Select the slice, commit/push tests and prove compatible assertion RED
before implementing any storage/route/thermal response.

Add only this boundary protocol in a new Recording source. Reading monotonic
time must not itself query capacity or increment capacity-read counters:

```swift
import Foundation

@MainActor
public protocol RecordingPressureSource: AnyObject {
    func availableBytes() throws -> Int64
    func nowNanoseconds() -> UInt64
}
```

Extend both owner initializers compatibly with optional `pressureSource`,
`storageReserveBytes: Int64 = 1_000_000_000`, and
`storagePollIntervalNanoseconds: UInt64 = 5_000_000_000`. Forward and retain them,
but do not inspect them, deny start or create a timer before actual RED. Existing
initializers and test bodies remain unchanged. Add only:

```swift
public func pollStoragePressure(sessionID: UUID) async {}
```

The eventual implementation must reject configurations below the one-billion-byte
minimum or otherwise enforce that minimum; the four cases here cover the chosen
one-billion-byte boundary, not arbitrary invalid configuration values. Add a
focused configuration test before claiming that broader rule is verified.

Add optional initializer closure parameters to IOSRecordingSignalMonitor and
store them unused. Current callers retain their real default boundaries:

```swift
inputAvailable: @escaping @MainActor () -> Bool = {
    !AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty
},
thermalState: @escaping @MainActor () -> ProcessInfo.ThermalState = {
    ProcessInfo.processInfo.thermalState
}
```

Do not add route/thermal observers or change existing interruption/reset behavior
until the new native tests have actually failed. The OS queries are the only
doubles; callbacks must not retain a raw non-Sendable Notification across an
executor hop. Stale signal epochs must retain their original identity.

Low-space behavior must reuse the combined existing owner cleanup barrier and
persist an interrupted meeting with an explicit `.storageFull` owner failure;
it cannot call ordinary Stop, publish Saved, then overwrite the row. Keep actual
ASR/SQLite drain, Activity acknowledgement, usage/model leases and explicit retry
semantics. No storage query, notification handling or inference goes in the tap.

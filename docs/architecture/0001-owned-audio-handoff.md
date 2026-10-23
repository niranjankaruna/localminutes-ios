# ADR 0001: owned bounded audio handoff

Status: selected for T05.1 tests first, not yet implemented or validated.

The AVAudioEngine callback must copy samples into app-owned, preallocated
storage and return promptly. The worker converts and persists samples outside
the callback. Queue lifetime belongs to the capture runtime, independent of
SwiftUI views. This decision does not establish microphone, background or
two-hour performance.

Use a fixed-capacity single-producer, single-consumer queue. Store planar
Float32 samples and primitive metadata; copy out into caller-owned scratch
storage before releasing a slot. Validate configuration and all allocation size
arithmetic before capture, including metadata in the 16 MiB storage budget.
Use a power-of-two capacity so slot selection remains correct when UInt64
indices wrap. No allocation, collection growth, actor/task creation, logging,
conversion or persistence belongs in enqueue/dequeue.

Use Swift's Synchronization.Atomic UInt64 load/store operations for publication.
Producer publishes a completed slot with release ordering; consumer acquires
the write index, copies the slot, then releases the read index. Producer
acquires the read index before reuse. Keep sample storage stable, and quiesce
both roles before destruction. An unchecked Sendable boundary must document
these ownership rules and be exercised by real parallel stress tests.

Swift 6.2.3 is the observed hosted compiler. Its standard-library source and
availability mapping support this API at the project's iOS18/macOS15 minimum.
SE-0410 requires supported atomic operations to be lock-free, while explicitly
not promising wait-freedom. This supports choosing index loads/stores; it does
not prove that the complete callback meets a real-time deadline.

Within one queue epoch, valid input attempts must be contiguous in source
sample time. The first may start at an arbitrary time. Full attempts advance
the source timeline and accumulate an exact fixed-size lost interval; invalid
attempts do not. Attach preceding loss to the next accepted chunk. After the
producer has stopped, finish must deliver any trailing loss exactly once.
The adapter must treat discontinuity, reset or route change as an explicit gap
or clean interruption/new epoch, rather than ignoring rejection indefinitely.

Tests must cover owned-copy fidelity, FIFO/slot reuse, variable lengths/stereo,
invalid dimensions/pointers/size overflow, integer index rollover, consecutive
and trailing loss, shutdown, undersized scratch storage and parallel ordering.
Later sanitizer, allocation inspection, native-adapter tests and physical-phone
endurance gates remain required; unit stress is not a substitute.

Primary references:

- [Pinned Atomic source](https://github.com/swiftlang/swift/blob/swift-6.2.3-RELEASE/stdlib/public/Synchronization/Atomics/Atomic.swift)
- [Pinned availability mapping](https://github.com/swiftlang/swift/blob/swift-6.2.3-RELEASE/utils/availability-macros.def)
- [SE-0410 atomic operations](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md)
- [SE-0282 memory model](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0282-atomics.md)

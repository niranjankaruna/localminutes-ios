import Synchronization

public enum CaptureCallbackEntryResult: Sendable, Equatable {
    case admitted
    case closed
    case overlapping
}

/// One stable object belongs to each tap epoch. The callback captures it for its
/// entire lifetime; replacement creates a new object and never reopens this one.
/// Entry and close linearize in one atomic state,
/// reject overlap before touching the SPSC queue, and never wait, allocate, create
/// tasks, operate on buffers or use a mutex in these methods.
public final class CaptureCallbackAdmission: @unchecked Sendable {
    // Bit zero is the sole admitted claim; bit one is monotonic closure.
    // One atomic state linearizes close against entry, without a retry loop.
    private let state = Atomic<UInt64>(0)
    public init() {}

    /// Only admitted callers may perform capture work and subsequently leave.
    /// Closed takes precedence over overlapping. Successful entry acquires
    /// the preceding leave publication when serial callbacks change threads.
    public func enter() -> CaptureCallbackEntryResult {
        let result = state.compareExchange(expected: 0, desired: 1, ordering: .acquiring)
        if result.exchanged { return .admitted }
        return result.original & 2 != 0 ? .closed : .overlapping
    }

    /// Call exactly once after an admitted entry, on that callback's exit. The
    /// caller owns this rule: there is no ownership token, and a caller must not
    /// release another callback's current claim. An idle/double leave returns
    /// false without changing state. A successful leave releases prior work.
    public func leave() -> Bool {
        state.bitwiseAnd(2, ordering: .releasing).oldValue & 1 != 0
    }

    /// Idempotently rejects future entry without releasing already admitted work.
    /// The control owner waits outside the callback for closed/quiescent before
    /// finishing the queue or releasing any storage used by admitted work.
    public func close() {
        _ = state.bitwiseOr(2, ordering: .acquiringAndReleasing)
    }

    /// True only after close and the last admitted leave. The atomic
    /// acquire must publish that callback's completed work to the control owner.
    public var isClosedAndQuiescent: Bool {
        state.load(ordering: .acquiring) == 2
    }
}

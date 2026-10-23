public enum CaptureCallbackEntryResult: Sendable, Equatable {
    case admitted
    case closed
    case overlapping
}

/// Test-first interface only. No admission state or algorithm exists until the
/// accompanying tests have a recorded native behavioral RED.
///
/// One stable object belongs to each tap epoch. The callback captures it for its
/// entire lifetime; replacement creates a new object and never reopens this one.
/// Eventual implementation must linearize entry and close in one atomic state,
/// reject overlap before touching the SPSC queue, and never wait, allocate, create
/// tasks, operate on buffers or use a mutex in these methods.
public final class CaptureCallbackAdmission: @unchecked Sendable {
    public init() {}

    /// Only admitted callers may perform capture work and subsequently leave.
    /// Closed takes precedence over overlapping. Successful entry must acquire
    /// the preceding leave publication when serial callbacks change threads.
    public func enter() -> CaptureCallbackEntryResult {
        .closed
    }

    /// Call exactly once after an admitted entry, on that callback's exit. The
    /// caller owns this rule: there is no ownership token, and a caller must not
    /// release another callback's current claim. An idle/double leave returns
    /// false without changing state. A successful leave releases prior work.
    public func leave() -> Bool {
        false
    }

    /// Idempotently rejects future entry without releasing already admitted work.
    /// The control owner waits outside the callback for closed/quiescent before
    /// finishing the queue or releasing any storage used by admitted work.
    public func close() {}

    /// True only after close and the last admitted leave. The eventual atomic
    /// acquire must publish that callback's completed work to the control owner.
    public var isClosedAndQuiescent: Bool {
        false
    }
}

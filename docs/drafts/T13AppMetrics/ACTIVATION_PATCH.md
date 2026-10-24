# Inactive minimal test-interface patch

Do not apply before selecting this slice. These declarations are only enough to
compile the new behavioral tests. They must remain no-op until the test-first
commit is pushed and hosted assertion RED is recorded. Existing working metrics
behavior and existing tests must remain unchanged.

In `LocalMinutesServices`, add an immutable optional field initialized to nil:

```swift
let metrics: TranscriptionMetricsRecorder? = nil

func persistMetricsCheckpoint() throws -> URL {
    throw MetricsValidationError.notImplemented
}

func exportMetrics() throws -> Data {
    throw MetricsValidationError.notImplemented
}
```

In `LiveTranscriptionSession`, expose only a read-only internal test seam for its
existing retained optional field. This adds no instrumentation or default wiring:

```swift
var metricsRecorder: TranscriptionMetricsRecorder? { metrics }
```

In `RecordingApplication`, import SwiftUI and add only the no-op boundary:

```swift
func recordScenePhase(_ scenePhase: ScenePhase) throws {}
```

After actual RED, production must construct exactly one default recorder using
validated values from the app bundle and the pinned speech manifest, pass the
same instance to the existing real Live session, map active/foreground,
background/background, inactive/unknown, and checkpoint each admitted visibility
change. Source identity must never be invented when absent or malformed.

Persistence must validate/encode the actual recorder snapshot and use the
existing `PersistentFilePolicy.writeAtomically` in a private owned Diagnostics
directory. Export returns the latest validated persisted bytes; missing or
invalid state is an explicit error. No diagnostic operation should download
models, request microphone permission, run inference or include meeting content.

The existing `beginEpoch` belongs to actual new audio reservations. Scene-phase
events must not reset counters. This slice does not add periodic timers or claim
checkpoint cadence during suspension; those require their own tests.

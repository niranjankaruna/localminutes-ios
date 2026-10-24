# Recovery integrity and global-gap regressions

Source review after d699 identified shape-only journal acceptance, captured-count versus global-timeline inconsistency, and a header-only CAF readability check. Three new real-CAF/SQLite regressions retain all original8 test bodies. No journal/gap/decode production repair precedes actual new assertion RED. Captured sample count is distinct from timeline extent; existing playback already accepts totalFrames=sum(captured segments) with a global gap. The new test requires one same manifest to recover and seek without changing that valid old assertion. Exact schema decision and implementation follow observed RED.

Concurrent Start/Delete/recovery still needs one app-lifetime usage admission; snapshots and per-instance sets do not establish it. Startup must settle pending deletions first and enumerate beyond default100. These are explicit remaining T08 requirements, not fulfilled by current component tests.

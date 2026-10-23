# T05.3 callback admission — uncompiled tests-first drafts

The adjacent `.swift.pending` files preserve the next small callback-lifetime
contract and nine tests. They are deliberately outside Core/Tests and are not
compiled, executed or implemented. No native RED/GREEN or microphone/device
evidence exists for them. The interface is only a no-behavior TDD stub.

First finish T05.2.1: push the committed selected-XCTest reporter regression,
prove hosted RED, fix strict reporting and obtain full exact-source native GREEN.
Then activate these files at `Core/CaptureCallbackAdmission.swift` and
`Tests/CoreTests/CaptureCallbackAdmissionTests.swift`, review and add required
discovery names, commit/push and prove meaningful native RED before implementing
the gate. Extend sanitizer coverage to this critical boundary. Keep one task
branch and the next invocation's CI/cost limits.
Activating these nine cases without other changes would make 65 XCTest expected;
that is a preparation count, not observed discovery or an executed result.

These tests address only atomic admission and shutdown ordering. They do not
complete T05.3: the real permission/session/AVAudioEngine adapter, conversion
worker integration, first-buffer readiness, stop flush and app ownership still
need their own tests and implementation. See ADR0002 and the unchanged backlog.

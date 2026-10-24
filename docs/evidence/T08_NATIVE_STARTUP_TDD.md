# TDD evidence record

Task/child ID: T08 native application startup/recovery composition
Requirement IDs: default app-owned startup, durable interrupted recovery, honest recording/model admission
Behavior being implemented: the actual application completes shared library startup before Start can enter its real model/OS preparation; a global startup failure leaves the owner pristine and denies recording.
Acceptance assertion: Start reconciles an interrupted 32-frame native CAF/SQLite fixture before returning the genuine missing-model rejection; a closed actual database produces cleanupPending/startup.failed and an idle owner rather than a model failure.

## RED — complete before production implementation

Test file and names: `Tests/NativeAppTests/NativeStartupIntegrationTests.swift`:

- `testAppStartReconcilesInterruptedCAFBeforeRealMissingModelRejection`
- `testClosedDatabaseStartupFailureLeavesOwnerIdleAndRefusesModelPreflight`

Minimal interfaces: internal `LocalMinutesServices.init(rootURL: URL? = nil)` stores only in an explicit owned fixture root when injected; default nil retains ApplicationSupport. Services constructs a startup-required registry/coordinator but never runs it; `initialize()` is no-op. `RecordingApplication(services:)` uses the same actual LiveTranscriptionSession/IOS permission/engine/Activity adapters and default fallback. Startup/admission is not wired into init/perform before RED.
Exact command and platform: pending root's hosted Xcode/iPhone Simulator app-hosted XCTest invocation.
Source commit: PENDING.
CI run URL / sanitized local log: PENDING.
Executed tests / skipped tests: NOT_RUN.
Observed assertion failure: NOT_RUN.
Why this proves missing behavior rather than a broken toolchain: requires actual compile and assertion failures; missing tools, permissions or setup are not RED.
RED commit pushed at: PENDING.

## GREEN

Implementation commit: NOT_IMPLEMENTED.
Exact command and environment: NOT_RUN.
CI run URL / sanitized result: PENDING.
Executed / passed / failed / skipped counts: NOT_RUN.
Real adapters exercised by tests: actual default app owner, native CAF writer/reader, SQLite with close/reopen, actual absent-model preflight. Real microphone/Activity creation is not expected because no speech model is installed.
Mock boundaries: no model/inference/permission/hardware doubles; only internal persistent-root injection selects generated synthetic fixture paths.
Regression suite and result: PENDING; all existing constructors/case bodies remain compatible.

## Review and continuation

Refactor commit(s): none.
Fault injection: closed real SQLite connection; no fake storage error or fabricated ASR readiness.
Security/privacy review: original synthetic files only in checked generated owned roots, bounded operation/cleanup waits, actual owner quiescence and SQLite close before root removal. No default owner model/meeting content is modified by these tests.
Remaining physical-device gates: protection, locked capture/start, Action Button, signing/renewal, refresh preservation and both 125-minute passes remain NOT_RUN.
Next task: root reviews and pushes this test-first slice; record actual native behavioral RED before startup/admission wiring. SPM startup-component RED/GREEN is not a native application composition result.

Pending/empty fields are unverified, never a pass. No model downloads, real meeting content or credentials are included.

Test-first source1f03e5259ead091c616eb4ce3c49f80d1af79018 pushed/remote verified, actual compatible RED pending [run40075611744](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40075611744). No new working behavior before assertions.


## Actual native app RED, 24 October 2026

Exacttest-first1f03e5259ead091c616eb4ce3c49f80d1af79018/run[40075611744](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40075611744), completednativejob120818174077:59app-hosted cases57pass2newfail15assertions0unexpected/skip; strictreporterandxcresultagree. StartleftstartupnotStarted/originalCAFmetadataunrecovered/nodurablereport. ClosedDBStartincorrectlyreachedmissing-modelpreflightandfailedownerinsteadofremainingidle/cleanupPending. Theseactualnativebehaviorfailuresauthorizeminimalservicesinitialize/start-togglegate/sharedregistryownerwiring. Bothdevice/simulatorbundlechecks2/2passafterstrictinspectionreorder. UI3/3passandxcresultagrees. Physical7compileonly/0executedNOT_RUN. Packagingnotrunafternewnativefailures;nocandidate. Noautomaticviewlaunch/replay/phonepassinferred.

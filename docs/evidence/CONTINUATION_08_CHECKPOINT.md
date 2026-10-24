# Continuation 08: exact-source checkpoint

Project state: **IN_PROGRESS**. No new top-level baseline feature is complete.
The current bounded invocation used six of six CI runs. All are terminal; do
not dispatch, rerun, or trigger a seventh run in this invocation.

## Verified source and result

Source: `db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` on `task/t06-activity`.
[Run 40079629180](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40079629180)
completed **SUCCESS** on 24 October 2026 at 09:07:57 UTC. All three jobs passed.
Tests used standard public `macos-15-intel`, Xcode 26.2 / build 17C52 and iOS
SDK 26.2. No paid runner, artifact upload, billing mutation, or cloud inference
was used. Later documentation-only HEADs must remain distinct from this source.

| Actual gate | Executed / passed | Failed / skipped | Job |
| --- | --- | --- | --- |
| Core XCTest, including actual CPU ASR, real SQLite/CAF and real HTTPS model installation | 269 / 269 | 0 / 0 | 120830277731 |
| Node script regressions | 59 / 59 | 0 / 0 | 120830277731 |
| Repeated ownership/queue tests under Thread Sanitizer | 85 / 85 | 0 / 0; no reported race | 120830277731 |
| Mandatory actual pinned native Qwen/b5046 tests | 5 / 5 | 0 / 0 | 120830277672 |
| App-hosted iOS XCTest | 59 / 59 | 0 / 0 | 120830277558 |
| Recording-control UI tests | 3 / 3 | 0 / 0 | 120830277558 |
| Pristine device/Simulator product inspection | 2 / 2 | 0 / 0 | 120830277558 |
| Real unsigned archive/CRC/hash/source and rejection tests | 13 / 13 | 0 / 0 | 120830277558 |

Strict named test reporters agree with the XCTest logs. Native and UI aggregate
counts also agree with actual xcresult summaries. The physical-file-protection
oracle compiled for iPhoneOS: **7 compiled, 0 executed, NOT_RUN**. Its source SHA256
remains `3abdf26b1175adc6919065931e9ed13193d5d9e2d45f01bbe73919e43bd37105`.
Simulator metadata does not establish actual protection on a locked iPhone.

## Test-first chain and resulting behavior

Earlier failing commits/runs remain in history, including
`cdf4a06f6a4a9cd226e306941fd0199a18bf418c` / 40038154279 (read after owner resume),
`d699fc5bfc266e03d8139869146fd55d7573fef9` / 40069154630,
`917844b016664251c545fb70106c50cfceb62694` / 40071855360,
`39d9eaa65f7b030a8bdf87e1447b254508dce2db` / 40073883889 and
`1f03e5259ead091c616eb4ce3c49f80d1af79018` / 40075611744.
Actual assertion failures authorized each subsequent behavior; compiler/tool
failures were not accepted as RED. The relevant TDD documents preserve commands,
assertions and source/run identities.

The final source includes these tested slices:

- **T08.2–T08.5:** actual CAF reconciliation/quarantine and rederived recovery
  journal, declared captured-frame validation and explicit timeline gaps;
  bounded unfinished-meeting pagination; coalesced startup with deletion replay;
  recording admission held through preparation and cleanup; native Start/Toggle
  waits for real startup before model preflight. This does not yet replay ASR
  from recovered audio, bind automatic HomeView launch, or establish admission
  across every independent recovery/delete coordinator.
- **T09–T11:** directory-authority regression repaired; actual pinned four-file
  HTTPS install, reopen/import/lease and CPU recognition pass. All ten recognizer
  and four live-composition cases pass. This is one licensed short speech fixture,
  not the complete required accent/noise/WER evaluation or locked endurance.
- **T12.1:** real filesystem hardlink/symlink and SQLite exact-file policy
  regressions pass, with all five Simulator-supported policy cases. Seven actual
  protection-class tests remain physical-only. OS interruptions, routes, storage
  reserve and thermal handling are unfinished.
- **T16.1–T16.3:** recoverable owned-deletion component, immutable note edit
  reservation and selection epochs, and eleven native playback/recording
  ownership cases pass. Safe Delete UI, request-scoped HomeView playback cleanup,
  continuous playback and complete backup/export remain unfinished.
- **T17.2–T17.3 / T18.1:** canonical prompt envelope, bounded caller-supplied flat
  grammar and actual native tokenizer/context boundaries pass. All four original
  semantic/model-size/cancellation oracles pass unchanged. The capacity fixture
  isolation and archived unexplained earlier failure remain explicitly documented
  in `T18_CAPACITY_FIXTURE_ISOLATION.md`; no semantic answer was enum-seeded.
- **T18.2:** six extractive grounding/merge cases pass, including exact selected
  source quotes/ranges, nullable attributes, conflicts and provenance. General
  semantic entailment and a complete generated-summary pipeline are not proved.
- **T19.1:** six actual SQLite FTS5 schema3 migration/retrieval cases pass, including
  legacy data preservation, lexical operators, selected-meeting isolation and
  posting maintenance. This is retrieval, not working Q&A generation.

The current-schema test expectation advanced to3 for the new FTS migration;
legacy v1/v2 fixtures and all original data-integrity assertions remain intact.
No tests were skipped or removed to manufacture the final result.

Source `8b653cb8c33b7abd2d83e747b7bc404d1900f5f5` / 40077503748 already passed
every application/model/UI group, but failed one strict archive negative fixture
because XCTest had signed/instrumented the reused Simulator product. Final
`db1b8d5` changes only workflow ordering: both product and archive checks run on
pristine compiled products before XCTest. The unchanged thirteen archive cases
now pass. Final standalone packaging still runs after native/UI tests.

## Ephemeral artifact, not delivery

The runner created and verified:

- Name: `LocalMinutes-1.0-db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04-unsigned.ipa`
- SHA256: `e3eba563ccbd549987a43ed29c5da591fbf3a41cfa5357fc96e99372b0f721c0`
- Size: **12,632,611 bytes**; created 2026-10-24T09:07:52.537Z.
- arm64 iOS, minimum iOS18.0, unsigned; app
  `com.niranjankaruna.localminutes`, extension
  `com.niranjankaruna.localminutes.LiveActivity`.

It was **not uploaded, retained, downloaded, signed or delivered**. Model weights
are not embedded. `candidateArtifact` remains null. Account artifact storage was
observed full; included headroom must be verified before future delivery. This
does not block independent development. No unrelated artifact was deleted.

## Next tests and remaining gates

Reviewed inactive drafts are saved outside active targets:

| Slice | Draft cases | Path | Evidence status |
| --- | --- | --- | --- |
| T12.2 owner interruption and native signal epochs | 3 | `docs/drafts/T12Signals/README.md` | Uncompiled / NOT_RUN |
| T13.1 bounded metrics, strict private export and actual-ASR integration | 5 | `docs/drafts/T13Metrics/README.md` | Uncompiled / NOT_RUN |
| T18.3 nested schema, map/validate/merge and mandatory actual Qwen | 5 | `docs/drafts/T18Pipeline/README.md` | Uncompiled / NOT_RUN |
| T19.2 selected-meeting answers/refusal and mandatory actual Qwen | 4 | `docs/drafts/T19QA/README.md` | Uncompiled / NOT_RUN |

No new runtime instrumentation, full summary pipeline or Q&A behavior is supplied
by these drafts. Actual-model classes must stay out of the model-free core
filter. Every new behavior still needs compatible assertion RED before repair.

**Exact next action:** in the next bounded invocation, read required documents,
verify Git/remote/current terminal CI and the zero-spend cost guard, then activate
the three T12.2 tests plus minimal stubs and strict case reporting. Commit/push
that test-first slice, demonstrate real hosted RED, then implement the bounded
interruption contract. The three other reviewed drafts can be delegated within
the same single-branch and six-run limits. Never reset the present run budget
merely to dispatch another run in this invocation.

Full summaries/Q&A and persistence/editing, global ASR/LLM admission, recovery ASR
replay, OS pressure/routes, metrics/UI, onboarding/accessibility/privacy review,
retained delivery and final audit remain required. The owner will perform both
125-minute iPhone tests. Free signing/extension, warm and locked-cold Action
Button, locked live transcription, offline iPhone inference, file protection and
in-place renewal/data preservation are all **NOT_RUN**. The baseline is neither
CODE_COMPLETE_PENDING_DEVICE nor VERIFIED_COMPLETE.

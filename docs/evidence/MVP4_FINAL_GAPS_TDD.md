# MVP4 final functional gaps — T12.5, T15.2, T18.7

## Acceptance and scope

The final read-only audit found three concrete requirements still missing in
the product, independently of phone tests and owner-manual model quality:

- T12.5 (R05/R07/R08): respond to real UIKit memory-warning notifications by
  cancelling/draining/unloading the current intelligence request. Preserve
  capture/streaming ASR and hold resource/model leases until work actually joins.
  See IMPLEMENTATION_GOAL.md section10, “Unload on memory pressure.”
- T15.2 (R08/R12): expose all local meeting history, title search beyond the
  newest100, explicit history/detail loading states, and later transcript search
  matches beyond the first50. Preserve ordering, literal queries and isolation.
- T18.7 (R10): make saved Q&A display text editable with durable serialized
  revision checks, conflict/reopen behavior and immutable original evidence,
  model provenance, source transcript and separate manual notes.

## RED — prepared, not yet claimed

Five actual SQLite/controller cases in `HistoryPaginationTests`; four native
memory-warning lifecycle cases in `NativeIntelligenceMemoryPressureTests`; five
real SQLite/controller cases in `NativeAnswerEditingTests`; two actual history
UI cases and one answer-edit/relaunch UI case. Names are required explicitly by
the `mvp4-final` workflow mode. No inference or quality benchmark is selected.

Only compileable empty seams have been added: no-op history/search paging;
false loading/hasMore flags; false answer saves/no-op reopen; a no-op warning
monitor and nil service ownership. A nil scheduling observer pauses only after
actual SQLite reads for deterministic loading assertions. The additional103-row
UI fixture is DEBUG-only, synthetic and token-owned; default fixtures remain
unchanged. Production SQL/editor/observer behavior awaits actual hosted RED.

Memory tests mock only runtime allocation/work/unload at the lifecycle boundary.
They emit no generated text and do not establish model inference, quality or
physical out-of-memory behavior. Installer digests, leases, SQLite and the real
UIKit notification name are exercised.

Test-first commit `b05e7d9730ecefea1c5ba216183cad928861fc8f` was pushed before
implementation. Actual RED source `3df777c9cc4beccf652294874e52f889bb9204c3`
adds only four documentation files to that exact executable/test code.
[Run40188134859](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40188134859)
is terminal FAILURE with genuine behavioral assertions after successful builds:

- Core job121153187659:5 cases,1PASS/4FAIL/14assertions/0skip,2.343s. Actual
  stored103-row history remained100; older title query did not change those rows;
  loading stayed false while actual reads were held;55 matches remained50.
- Native job121153187938:9 cases,1PASS/8FAIL/20assertions/0skip,7.722s. Memory
  group4:1PASS/3FAIL,4.295s (nil observer, active work/load never cancelled).
  Answer group5:0PASS/5FAIL/17assertions,3.427s (unchanged text/revision,
  duplicate-save false results, no conflict/reopen/navigation save).
- UI job121153187939:3 cases,0PASS/3FAIL/3assertions/0skip,203.959s. Actual
  Beta answer lacked an editor (142.167s); actual103-row history lacked Load more
  and could not find its oldest title (two cases61.793s).

Compiler/tool failures or zero cases are not RED. None were used as RED here.

## GREEN

All three corresponding RED groups were observed before their production
behavior. Minimal memory observer/cleanup, SQLite/controller paging/loading and
answer CAS/editing/controller/UI are implemented. Root and independent Medium
peer review found no concrete blocking issue; actual GREEN remains pending.

The final batch uses related portable regressions, one app-hosted regression
group, two parallel UI groups (history/information and answers/library), and one
actual Release package/hygiene job. UI-only scheme omits compiling the unrelated
app unit-test bundle while retaining the same real app/UI targets and explicit
required-case verification. Build6 metadata advances both existing exact-build
assertions together. No model-quality jobs or full suite per edit.

Pending one final combined regression/device-package run, exact-source
verification and downloaded bytes.
Phone signing/extension, offline use, locking/Action Button, endurance, physical
protection and renewal remain owner-owned NOT_RUN and are not development PASS.

## Review and continuation

Preserve the storage-report GREEN from source3273fb2/run40186443609 only for its
actually completed compatible scope; check remaining native/UI/package results.
Do not call MVP4 development complete while the three missing behaviors remain.
No full suite per edit or automated model-quality evaluation. Next: one focused
tests-first batch, implement only after the corresponding behavioral failures,
then a combined final regression/package batch and deliver the verified IPA.

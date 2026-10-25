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

Source commit/run/observed assertions: pending. Compiler/tool failures or zero
cases are not RED. Push this test-first change before production implementation.

## GREEN

Pending actual RED, minimal implementation, one final combined app regression
and device-package run, exact-source verification and local downloaded bytes.
Phone signing/extension, offline use, locking/Action Button, endurance, physical
protection and renewal remain owner-owned NOT_RUN and are not development PASS.

## Review and continuation

Preserve the storage-report GREEN from source3273fb2/run40186443609 only for its
actually completed compatible scope; check remaining native/UI/package results.
Do not call MVP4 development complete while the three missing behaviors remain.
No full suite per edit or automated model-quality evaluation. Next: one focused
tests-first batch, implement only after the corresponding behavioral failures,
then a combined final regression/package batch and deliver the verified IPA.

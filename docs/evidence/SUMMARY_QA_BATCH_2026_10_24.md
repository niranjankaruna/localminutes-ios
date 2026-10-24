# Summary/Q&A functional batch —24October2026

State: **IN_PROGRESS**. App integration/screens implemented and compiled; the local-model quality gate is **FAILED**, so summaries and Q&A are not complete.

## Code and artifact

Final app source: d6a329354ffc095d4dffb9ca4d939c67bf10adc8. Build-only run: https://github.com/niranjankaruna/localminutes-ios/actions/runs/40101392948 —SUCCESS14:14:54UTC,0tests executed. Actual iPhone arm64/iOS18+ app and embedded Live Activity extension compiled with Xcode26.2/SDK26.2.

Unsigned IPA: LocalMinutes-1.0-d6a329354ffc095d4dffb9ca4d939c67bf10adc8-unsigned.ipa
Size: 12931428bytes
SHA256: 4b89ee364976f661ab206ef914f73746a2c976f5ab2a1b72acb46037d910f19d
Local directory: build/delivery/Summary-QA-40101392948
Unpublished draft release:422770453/tagmvp-preview-d6a329354ffc
Downloaded bytes match runner manifest and GitHub digest. No weights/private meetings/credentials/signing files in the IPA.

The original recording MVP remains in build/delivery/MVP-40092475736. This preview migrates metadata to schema4; the older schema3 MVP cannot reopen that upgraded database. Original rows are retained, but downgrading the old binary is not a supported rollback.

## Implemented

Actual retained IntelligenceSession/default pinned CPU runtime, one shared ASR/LLM gate, capture-priority model drain, selected Summary/Ask, separate generated-original JSON and serialized CAS editable copy, selected saved questions, original source quotes/playback, cancellation/background cleanup and generated-content export. No visual redesign. Input packs by actual canonical tokenizer; output≤2items/category with1citation, original validation/global limits preserved. No response rewriting, mocked inference or test/pin weakening.

## Actual observations

1. 1eeb403f864d5532b8046bf4e8c270f5614399bb / run40098679075: app buildSUCCESS. Three actual model cases FAIL: summary unsupportedClaim88.333s, default service summary unsupportedClaim123.126s, QA5known-budget refusal assertions130.030s. A faithful whole-labelled commitment was wrongly rejected by its body-only lookup.
2. 588834b68876e94a6cffe5963fe0a875d1f69315 / run40099854249: app buildSUCCESS. Narrow validator repair now admits the faithful single first-person quoted commitment, keeping owner/deadline/source/negative checks; positive summary assertions pass and the captured second unknown fixture is reached. Full summary case stillFAIL196.566s: model outputs task Reviewthechecklist,ownerunassigned and a non-deadline sentence as due, correctly rejected. Default service summary stillFAIL313.242s. QA stillFAIL114.555s unsupportedEvidence; raw failed question stage not captured, no inferred positive PASS.
3. d6a329354ffc095d4dffb9ca4d939c67bf10adc8 / run40101392948: final compile/package-only. No repeated model or full regression run. Input-source packing restored to avoid an artificial256-utterance cutoff; the two-source observation fixtures have identical chunks/prompts/schema.

All original semantic assertions, native model/hash pins, source domains and unconstrained generated quotes remain. The rejected unknown outputs were not normalized into passing values. Three unsuccessful QA prompt repairs stopped; a bounded retrieval-precision repair used ownership morphology/term coverage and top1 source for the one-quote contract. It did not resolve the quality gate. No4thblindprompttrial.

## Handoff

Usage/known limits: docs/SUMMARIES_AND_QA.md. Physical signing, ActionButton, locked continuation/coldstart, two owner125minute passes, renewal and private file protection remain NOT_RUN. Long-meeting quality, notes-only citations/checkpoint resume and broader baseline work remain pending.

Owner was asked whether to allow one compatible-model comparison capped30minutes or stop model work. The choice remains pending. Microsoft Phi-3-mini-4k-instruct-GGUF was identified read-only as a possible MIT-licensed2.2GB Q4 candidate, not downloaded/pinned/evaluated or claimed working: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf. No further inference/test/CI loop is scheduled while awaiting the choice.

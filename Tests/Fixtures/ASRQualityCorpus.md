# Bounded public ASR quality batch

This fixed set contains three public LibriSpeech test-clean clips: 45.85 seconds,
116 reference words and three distinct speakers. The JSON contains metadata and
publisher references only. Audio stays in ignored `.agent-local/asr-quality-corpus`.
Attribution and CC-BY-4.0 terms are declared by the original publisher:
https://www.openslr.org/12/ and https://huggingface.co/datasets/openslr/librispeech_asr.
The references are the publisher dataset's exact text, not model-generated labels.

No actual model evaluation result exists from preparing these tests. Audiobook
read speech does not establish owner-accent, modern technical-meeting, natural
room noise, multi-party conversation, or physical-phone accuracy.

Run `python3 scripts/prepare_asr_quality_corpus.py` on hosted macOS, then set
`LOCALMINUTES_ASR_CORPUS_DIRECTORY=$PWD/.agent-local/asr-quality-corpus`.
The preparer retrieves only individual public audio slices, verifies ID/reference,
immutable asset revision, exact original bytes/SHA and FLAC stream metadata. A
changed publisher asset fails verification; signed temporary URLs are never
stored or logged. No model is downloaded by this preparer.

Use the existing pinned model preparers and their original environments:

- Zipformer: `LOCALMINUTES_ASR_MODEL_DIRECTORY`, `LOCALMINUTES_ASR_FIXTURE_PATH`.
- Parakeet: `LOCALMINUTES_PARAKEET_COREML_MODEL_DIRECTORY`,
  `LOCALMINUTES_PARAKEET_COREML_FIXTURE_PATH`.

The unchanged existing model helpers also require their original short licensed
fixture to verify readiness. These tests load the actual CPU runtimes, never
boundary doubles. Run the two model cases in separate standard hosted macOS jobs,
with bounded job timeouts, using these exact filters:

```
ASRTests[.]ASRCorpusQualityTests/testActualStarterZipformerCleanAnd15dBNoiseCorpusWordErrorRates
ASRTests[.]ASRCorpusQualityTests/testActualNativeParakeetCleanAnd15dBNoiseCorpusWordErrorRates
ASRTests[.]ASRCorpusScoringTests
```

Each model processes three clean clips and three controlled-noise derivatives.
Noise is generated only after actual PCM decoding: LCG64 with wraparound multiply
6364136223846793005/add 1442695040888963407, seed from the first 16 hexadecimal
characters of the source SHA, high 32 bits mapped uniformly to [-1,1). Full-clip
signal/noise energy sets 15 dB SNR. A shared signal+noise gain keeps the mixed peak
at most 0.99; there is no clipping or silent sample deletion. The test records the
actual measured SNR, seed, gain, source SHA and resulting Float32 little-endian SHA
after generation. No derived checksum is invented in advance.

Scoring lowercases Unicode text and splits at every non-letter/non-number.
It does not stem, map synonyms, replace numbers or alter the hypothesis. Full
reference Levenshtein counts substitutions/deletions/insertions; equal-cost paths
prefer substitution, deletion, insertion. Aggregate WER sums edits over all 116
reference words per condition, with thresholds <=15% clean and <=25% controlled
noise. Every clip's edit counts/WER and total are logged; no clip is discarded.
Observed public-only records are saved in the ignored corpus directory even when
quality assertions fail. A missing model, audio, or native decoder fails instead
of skipping. Parakeet ingestion stays within its five-second call limit.

These are additional bounded accuracy checks, not a replacement or weakened
version of the original streaming/model-integrity oracles. Passing them would
still leave Goal 17.3's representative meeting/owner-accent evaluation pending.
Whisper's optional model quality scope remains separate and unchanged.

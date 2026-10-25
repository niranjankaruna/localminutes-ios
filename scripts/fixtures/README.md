# Native frameworks and licensed test fixtures

Run helpers from the repository root. Downloads are pinned and verified; generated
files stay in ignored `.agent-local/`. These helpers prepare inputs, not inference
results. Model and audio preparation is opt-in through the hosted workflow.

Three workflow jobs can check out historical app sources. They select the one
tracked summary helper from that revision, retaining its original draft path
when replaying old commits. Current-source jobs use `scripts/fixtures/`.

| Helper | Purpose |
| --- | --- |
| `prepare_native_summary.py --framework-only` | Pinned llama.cpp and Whisper frameworks without model weights |
| `prepare_native_summary.py` | Also prepares the historical Qwen test fixture |
| `prepare_native_fixture.py` | Pinned streaming Zipformer and licensed LibriSpeech audio |
| `prepare_whisper_fixture.py` | Pinned Whisper framework, model, and licensed audio |
| `prepare_native_parakeet_fixture.py` | Reviewed Parakeet Core ML subset and licensed audio |
| `prepare_phi3_candidate.py` | Historical Phi-3 comparison fixture; does not change the equipped app model |

The ASR-only framework builder and corpus preparation remain at
`scripts/prepare_asr_only.py` and `scripts/prepare_asr_quality_corpus.py`.
Quality tests and their historical results are preserved; automated model-quality
benchmarks are not a current delivery gate. Missing inputs or setup failures do
not count as behavioral RED or a successful native test.

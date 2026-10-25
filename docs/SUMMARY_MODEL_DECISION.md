# Historical summary starter-model decision, 24 October 2026

Current policy, 25 October 2026: the owner chooses models manually and does not
intend to use Phi-3 for summaries. Automated model-quality benchmarks are not an
MVP3 delivery gate. The decision and actual results below are historical evidence,
not a current recommendation. See [model setup](MODELS.md).

The app's starter summary choice moves from Qwen2.5-1.5B Q4_K_M to Microsoft's
Phi-3-mini-4k-instruct Q4. This is a model configuration change after actual
quality RED/GREEN, not a new untested inference engine or prompt workaround.

Qwen's actual unknown-attribute/grounding cases remain recorded failures; their
oracles and tests stay in the repository. Phi's two independent summary cases
pass at c26880d/run40109131483, and its real installed default-loader integration
generates/saves a summary and selected-meeting answer at
d0fe973/run40114656922 (1PASS,571.357s,hosted Intel CPU). Previous Phi known-answer
and unknown-owner refusal observations also remain recorded. These small
fixtures establish working flows, not representative meeting quality or phone
latency/endurance. Existing source validation is unchanged.

Reviewed pin: microsoft/Phi-3-mini-4k-instruct-gguf,
a64113399c2f6b8ad3e11c394733a2ddadaa7f33,
Phi-3-mini-4k-instruct-q4.gguf,2,393,231,072bytes,
SHA256 8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef,
MIT. Runtime remains pinned CPU llama.cpp b5046, context4096. More disk/RAM is
needed than Qwen1.5B; the browser shows advisory resources and actual phone
facts. Actual on-phone memory/speed remains pending.

Owners can install multiple compatible public Hugging Face alternatives and
equip one summary choice. Existing Qwen installations and meeting data are
preserved; they remain visible in installed models and can be explicitly
equipped. No automatic model download, data migration, weight bundling or
background inference is introduced. Unknown architectures/templates must be
reported unsupported/unverified rather than promised runnable.

# T17 canonical Qwen prompt formatter — test first

Observed23October2026,23:08UTC. This is a separate formatting contract, not a
new blind prompt retry or proof of a semantic-quality repair.

## Actual source metadata

Official model: Qwen/Qwen2.5-1.5B-Instruct-GGUF, immutable revision
`91cad51170dc346986eccefdc2dd33a9da36ead9`, artifact
`qwen2.5-1.5b-instruct-q4_k_m.gguf`,1,117,320,736bytes, SHA256
`6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`.
Actual local bytes were rehashed and matched before metadata extraction.

Python standard-library code read the GGUFv3 header and metadata key/value
table, sought past unrelated typed values/arrays, and decoded the UTF8 value
of **tokenizer.chat_template**. No Jinja/template code or model inference was
executed. Model metadata also reports architectureqwen2 and
nameqwen2.5-1.5b-instruct. Actual model and extracted JSON remain ignored:

```text
.agent-local/qwen-research/qwen2.5-1.5b-instruct-q4_k_m.gguf
.agent-local/qwen-research/qwen-91cad511-chat-template.json
```

`git check-ignore` confirmed the extracted JSON is ignored. With explicit
system/user messages, no tools, and add_generation_prompt, the pinned template
specifies this canonical envelope (`\n` means one newline):

```text
<|im_start|>system\n{system content}<|im_end|>\n
<|im_start|>user\n{user content}<|im_end|>\n
<|im_start|>assistant\n
```

The template adds no extra newline between message content and im_end. The
current LocalSummaryRuntime manual Swift multiline string inserts such a
newline and ends its assistant header without the required final newline.
This is a source-formatting discrepancy. It does **not** prove the discrepancy
caused the observed wrong owner/task/deadline: Windows runs using the model's
normal chat template also misattributed the action. The production GBNF is
generic JSON and contains no fixed fictional names/dates or answer literals.

## Test-first source; RED pending

New tests: `Tests/SummaryTests/SummaryPromptFormatterTests.swift`.
Minimal compileable no-op interface: `Summaries/SummaryPromptFormatter.swift`,
whose format function returns an empty String. LocalSummaryRuntime generation
behavior and the original four semantic assertions remain unchanged.

Required case inventory:

```text
testCanonicalPinnedQwenEnvelopeHasFinalAssistantNewline
testControlTokenDelimitersAreEscapedAsContentInBothMessageRoles
testUnicodeAndOrdinaryMarkupArePreservedWithoutNormalizationOrTruncation
testByteLimitCoversTheWholeCanonicalEnvelopeAtItsExactBoundary
testUnicodeAndEscapingExpansionAreIncludedInUTF8Budget
testInvalidByteLimitsAreRejectedWithoutSilentlyDroppingEvidence
testEmptyUserMessageStillHasSeparateCanonicalRoles
```

The escaping contract breaks content's `<|` control delimiters with U+200B;
only formatter-owned role tokens remain special. Ordinary Unicode bytes,
combining forms, markup and meaningful trailing content newlines are retained.
The full encoded envelope, including escaping expansion, must fit its UTF8
budget; reject rather than truncate evidence. These are formatting/security
assertions, not proof of resistance to every semantic prompt injection.

Compatible command: `swift test --enable-code-coverage --filter
SummaryPromptFormatterTests` on hosted macOS/Xcode26.2, with the pinned native
binary prepared for package evaluation. Root will include the seven names in
the next strict core test inventory. Source SHA/run/actual failures are
**PENDING**. Windows text/whitespace review passed; no Swift compile or RED is
claimed. Obtain meaningful hosted assertion RED before implementing or wiring
the formatter, then prove focused/regression GREEN. Keep the original actual
model quality gate mandatory and preserve its correct owner/evidence assertions.

Test-first sourcecdf4a06f6a4a9cd226e306941fd0199a18bf418c pushed and remoteHEAD verified before implementation. Hosted run40038154279 active; compatible assertion RED remains pending.

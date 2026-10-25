# LocalMinutes on Windows: installation and seven-day renewal

Official instructions rechecked on **24 October 2026**. This is the Windows 11
route using a free Apple Account and accepted seven-day renewal; it requires no
owned Mac, local Xcode or paid Apple Developer membership. Hosted macOS builds
are a separate development step.

**Installation update, 24 October 2026:** the owner reports successful installation
with **iLoader**, now the selected Windows installer. The exact installed IPA and
iLoader version remain unreported. The owner
reports iPhone 17 Pro / iOS 27.0.1. The delivered build 7 candidate is listed in
[STATE.json](STATE.json); full physical-device acceptance remains pending.
Installation does not establish
extension, locked-screen, offline or renewal results.

**Current checkpoint, 25 October 2026:** [model-upgrade build 7](MODEL_UPGRADE_BUILD7.md)
is delivered with passing focused native/model/UI/package checks. The owner
reports iPhone 17 Pro / iOS 27.0.1. Exact installed build, iLoader version and all
phone acceptance observations remain unreported. Use the candidate guide/checksum,
[model-upgrade checks](MODEL_UPGRADE_DEVICE_CHECKLIST.md) and
[physical-device checklist](MVP4_DEVICE_CHECKLIST.md).

## Before installing a candidate

Use a candidate whose manifest names the exact tested source commit. Download
its unsigned IPA, SHA-256 file, build manifest and known limitations together.
Compare the IPA's SHA-256 with the supplied checksum before opening it in
iLoader; Windows PowerShell provides `Get-FileHash -Algorithm SHA256`.
Do not install a simulator app or a file from an unverified download source.
Model weights are installed separately in the app, after their integrity is
verified; they are not included in the normal IPA.

Record the actual phone model, iOS, storage, app version and signing-tool version
in a copy of [DEVICE_TEST_REPORT.md](templates/DEVICE_TEST_REPORT.md). The build
targets iOS 18 or later. Apple's Personal Team limits include ten App IDs, three
registered devices and three installed apps per device, with seven-day expiry.
The main app and extension's actual registration/signing capacity is unmeasured.
[Apple account limits](https://developer.apple.com/help/account/basics/about-your-developer-account)

## Install with iLoader and the owner's free Apple Account

1. Get the Windows desktop installer from [iLoader's official site](https://iloader.app/)
   or its [official repository](https://github.com/nab138/iloader). The official
   Windows prerequisites list iTunes. Follow the current prerequisite links;
   retain the Apple components that already work with the owner's installation.

2. Connect the iPhone by USB and unlock it. Complete the computer trust prompts
   in iTunes and on the phone. Enter the passcode on the phone when requested.
   [Apple computer-trust instructions](https://support.apple.com/en-ie/109054)

3. In iLoader, choose the phone and its custom IPA installation option, then
   select the verified LocalMinutes unsigned IPA. The owner handles Apple
   Account sign-in and 2FA **locally in iLoader**, never in chat, files or CI.
   Keep the embedded Live Activity extension if any option asks about removing
   extensions. Record the actual installed identifiers and retain those settings
   for renewal. Build identifiers are `com.niranjankaruna.localminutes` and
   `com.niranjankaruna.localminutes.LiveActivity`; extension installation still
   requires its own phone evidence.

4. Complete any developer-profile trust prompts under Settings → General →
   VPN & Device Management → the signing account. Follow the phone's actual
   prompts. If required, enable Settings → Privacy & Security → Developer Mode,
   restart, unlock and confirm.
   [Apple Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

5. Open LocalMinutes unlocked and use **Models → Speech**. Look up a supported
   repository, review compatibility, choose its supported files, then use
   **Download selected model** or **Import selected model from Files**. After
   verification, choose **Equip**, then use **Record → Start Recording**. Handle
   microphone/Live Activity prompts and record what appears.
   The owner's installation report alone does not establish an extension pass.

## Models and a short first test

Models supports repository lookup, verified downloads and Files imports.
Downloading or importing and equipping are separate actions. Equip one Speech
model and one Summary model independently; keep the original speech installation
available for any meeting whose unfinished transcript needs recovery.

| Model | Supported selection | Intended use |
| --- | --- | --- |
| Streaming Zipformer | Reviewed matching encoder, decoder, joiner and tokens set | CPU local streaming transcription |
| Whisper | Compatible Whisper GGML `ggml-*.bin` file | CPU chunked transcription |
| Parakeet v2 | Reviewed FluidInference Core ML conversion, with all required bundles and vocabulary | Chunked local transcription; see the candidate's compute policy |
| Summary model | Compatible Qwen2/Phi3-family GGUF with a supported template | Local summaries and selected-meeting questions after recording; owner chooses the model, Phi-3 is not required |

Use the [current build guide](MVP4_GUIDE.md), [model setup](MODELS.md), and
[library/backup guide](LIBRARY.md). MVP3 and build6 use CPU-only Parakeet;
evidence from an earlier CPU/Neural Engine configuration
cannot validate that changed runtime. Fresh phone checks are required.

Models are separate from the IPA. File verification checks integrity;
phone recognition and endurance still need their own evidence. Keep the model
revision/checksums from the candidate manifest with each report.

Use original, non-sensitive speech for a short unlocked recording. Require
**Recording is active**, evolving local transcript text, a completed Stop, and a
saved meeting under **Meetings**. Check its transcript, original notes and segment
playback. Missing models or pending cleanup are not a successful recording. After
model installation, repeat with network access disabled to check the actual
offline path. Stop recording before generating a summary or asking questions,
keep the app open, and review generated claims against their sources. Compatible
files and download success do not establish answer quality or long-meeting
performance; existing Qwen quality limitations remain documented.

## Action Button: measure each start mode separately

In Shortcuts, create a shortcut containing LocalMinutes' **Toggle LocalMinutes
Recording** action (some pickers use the short label **Toggle Recording**). Name
it **LocalMinutes Toggle**. In Settings → Action Button, select **Shortcut** and
choose that shortcut. Apple requires choosing a specific shortcut, then pressing
and holding the Action Button to run it.
[Apple Action Button instructions](https://support.apple.com/en-ie/guide/iphone/iphe89d61d66/ios)

Record these as separate observations:

- **Warm/unlocked:** open the app, then use the button to start and stop.
- **Locked continuation:** start unlocked, lock the phone, and test the Live
  Activity's status and Stop control without unlocking.
- **Locked cold start:** after permissions are set, restart, unlock once, then
  lock again without reopening LocalMinutes. Try the button and record whether
  it starts, requests unlock, or fails. Record how the cold state was established.

A warm pass does not pass cold start. An unlock-required result is an explicit
fallback, not a waived requirement. Free extension installation and all of these
phone behaviors remain **NOT_RUN**.

## Renew without deleting the app

Finish recording before renewal. Before the seven-day profile expires, connect
the phone to Windows and use **iLoader** to install the IPA over the existing
app with the **same Apple Account and actual installed bundle IDs**. Retain the
identifier settings used during the successful installation and preserve the
embedded Live Activity extension. Keep the existing app installed throughout.

Manual USB renewal is the documented project procedure. Successful initial
installation does not establish weekly refresh or data preservation. Use the
checks below to verify meetings, models, settings and shortcuts after renewal.

Keep any exported real meeting backup local and private. Never attach recordings,
transcripts, Apple credentials, profiles or raw device logs to GitHub.

Before a manual refresh, preserve the existing installation and verify a usable
backup of anything important. A local Windows device backup is an additional
precaution: use iTunes **Summary → Back Up Now** and check its completion date.
[Apple Windows backup instructions](https://support.apple.com/en-ie/108967)

**Backup limitation:** LocalMinutes requests system-backup exclusion for its
private storage. A device backup is therefore not proof that its meetings/models
are recoverable. **Share text / Share Markdown** exports omit raw audio, the
database and model installations. For a complete meeting-library backup, use
**Meetings → Library actions → Create library backup**, then **Save or share
library backup**. The folder contains private meeting data, including audio;
models and credentials are separate.

To restore, choose **Restore library backup…**, select the complete backup
folder and confirm after saving edits and stopping recording, playback and
processing. The previous library is retained; installed model storage stays
separate. Validate restoration with disposable synthetic meetings before relying
on it for important data. Keep original reference audio and exports locally;
do not delete a good installation to work around a renewal problem.

For the preservation test, record the actual installed identifiers, synthetic
meeting title/note/transcript/audio duration, model revisions and expected hashes.
Renew in place, reopen that same meeting, compare its data/playback, and repeat a
short offline recording, Live Activity and Action Button test. Use **Meetings →
Library actions → Prepare recording report**, then **Share sampled recording
report** for bounded diagnostic samples. Record unavailable evidence as
unavailable. Stable IDs and a successful iLoader installation do not prove this
app's data preservation. Keep only a sanitized result in the repository.

## Owner-run endurance: two separate 125-minute passes

Begin only after a delivered candidate passes the short phone tests. Copy
[DEVICE_TEST_REPORT.md](templates/DEVICE_TEST_REPORT.md) for **each** pass; use the
same source/model versions or explicitly record any change. Use a separate
report for in-place renewal and its preservation checks. For the CPU-only MVP3
candidate, both long passes must identify the new delivered candidate rather
than reuse evidence from an earlier compute policy.

1. Note IPA checksum, installed IDs, phone/iOS, model pins, audio route, storage,
   battery/charging, Low Power Mode, consent and network state. Play permitted
   reference speech from another device; do not use the recording iPhone as the
   source player. Keep the reference and timing record locally.
2. Start recording and confirm actual text before locking. Record start and lock
   times with an independent clock. Keep the phone locked for **at least 120
   continuous minutes** within a recording of **at least 125 minutes**. Do not
   refresh, restart or force-quit during the pass.
3. Observe the Live Activity without unlocking. At the end use its Stop control,
   record stop/unlock times, then check saved audio duration, speech near the
   beginning/end, transcript timing, gaps and original notes. Record any failure
   or required unlock rather than assuming success.
4. Repeat as a second independent pass. Complete the report's latency, backlog,
   memory, thermal, battery, audio and accuracy fields using actual measurements.

**Locked ASR requires separate evidence:** a Live Activity timer or a transcript
seen after unlock cannot establish that recognition progressed while locked.
After each pass, use **Meetings → Library actions → Prepare recording report**,
then **Share sampled recording report**. Keep the report locally and record its
hash alongside independent lock/start/stop times. Its sampled processing,
backlog, memory, thermal, battery and route facts are evidence inputs; app
background state alone does not prove that the phone was locked. Require
processed-sample/timestamp evidence tied to the locked interval and owner
observations. Mark absent measurements **NOT_AVAILABLE** and leave the
locked-live gate **UNVERIFIED** when evidence is insufficient.

Keep detailed evidence privately. A sanitized report can reference local evidence
hashes and the exact candidate; [VERIFICATION.md](VERIFICATION.md) is the index.
No actual endurance report has been produced by these instructions.

## Evidence still required

Main-app installation is owner-reported. Exact installed-build/signing details,
embedded-extension signing, actual installed identifiers, Live Activity
rendering and Stop control, Action Button warm and locked cold-start behavior,
phone-offline inference, live locked transcription, both 125-minute endurance
passes and renewal preservation all remain **NOT_RUN**. Test each separately.
If starting while locked requires unlocking, report that observed fallback
explicitly; only the owner can waive the desired cold-start experience.

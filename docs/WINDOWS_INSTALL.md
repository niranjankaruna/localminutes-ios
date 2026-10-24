# LocalMinutes on Windows: installation and seven-day renewal

Official instructions rechecked on **24 October 2026**. This is the Windows 11
route using a free Apple Account and accepted seven-day renewal; it requires no
owned Mac, local Xcode or paid Apple Developer membership. Hosted macOS builds
are a separate development step.

**No LocalMinutes IPA is available yet:** `docs/STATE.json` still records
`candidateArtifact: null`. No installation, extension, phone or renewal result
has been verified. Follow the installation steps only after a checksummed,
exact-source candidate is actually delivered.

## Before installing a candidate

Use a candidate whose manifest names the exact tested source commit. Download
its unsigned IPA, SHA-256 file, build manifest and known limitations together.
Compare the IPA's SHA-256 with the supplied checksum before opening it in
Sideloadly; Windows PowerShell provides `Get-FileHash -Algorithm SHA256`.
Do not install a simulator app or a file from an unverified download source.
Model weights are installed separately in the app, after their integrity is
verified; they are not included in the normal IPA.

Record the actual phone model, iOS, storage, app version and signing-tool version
in a copy of [DEVICE_TEST_REPORT.md](templates/DEVICE_TEST_REPORT.md). The build
targets iOS 18 or later. Apple's Personal Team limits include ten App IDs, three
registered devices and three installed apps per device, with seven-day expiry.
The main app and extension's actual registration/signing capacity is unmeasured.
[Apple account limits](https://developer.apple.com/help/account/basics/about-your-developer-account)

## Install with the owner's free Apple Account

1. Get Sideloadly for Windows from its official site. The checked site lists
   version 0.71.0 and requires the **web versions of iTunes and iCloud**, rather
   than their Microsoft Store versions. Follow its current prerequisite links;
   this guide does not freeze old Apple installer download addresses.
   [Official Sideloadly download and prerequisites](https://sideloadly.io/)

2. Connect the iPhone by USB and unlock it. Complete the computer trust prompts:
   select the device in iTunes and continue when prompted, then tap Trust on
   the phone and enter its passcode when requested.
   [Apple computer-trust instructions](https://support.apple.com/en-ie/109054)

3. In Sideloadly, select the connected phone and the verified unsigned IPA.
   Use Apple Account sideloading. The owner enters Apple authentication and
   handles 2FA **locally in Sideloadly**, never in chat, repository files or CI.
   Leave **Remove Extensions/PlugIns disabled**. Keep the same bundle-ID
   configuration on every renewal. Record any identifiers Sideloadly actually
   rewrites; free signing of this specific extension is still unverified.
   The build identifiers are `com.niranjankaruna.localminutes` and
   `com.niranjankaruna.localminutes.LiveActivity`.
   [Sideloadly features](https://sideloadly.io/)

4. If iOS reports Untrusted Developer, Sideloadly's FAQ directs the owner to
   Settings → General → Profiles / VPN & Device Management → the signing
   account → Trust. Follow the actual free-development prompts on the phone.
   [Sideloadly FAQ](https://sideloadly.io/faq.html)

5. If required, enable Settings → Privacy & Security → Developer Mode, restart,
   unlock, confirm Enable and enter the phone passcode. Apple describes
   installing a development-signed app without Xcode as a way to expose this
   menu. Record actual availability on the owner's iOS version.
   [Apple Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device),
   [Apple explanation of installation without Xcode](https://developer.apple.com/videos/play/wwdc2022/110344/)

6. Open LocalMinutes unlocked and use **Models → Offline speech → Download
   speech model**. Wait for **Speech model verified**, then use **Record → Start
   Recording**. Handle any microphone/Live Activity prompts on the phone. Record
   what actually appears; an app icon does not prove the extension installed.

## Models and a short first test

The current screens provide downloads, not a Files import picker:

| Model | Screen download | Intended use |
| --- | --- | --- |
| Pinned sherpa-onnx streaming English int8, revision `672fbf1b30579d6585301139bb363f42a0ad4a24` | 73 MB | Required local live transcription |
| Pinned Qwen2.5-1.5B-Instruct Q4_K_M, revision `91cad51170dc346986eccefdc2dd33a9da36ead9` | 1.12 GB | Optional download; summary/Q&A pipeline and UI remain unfinished |

Models are separate from the IPA. The verified label checks the pinned files;
phone recognition and endurance still need their own evidence. Keep the model
revision/checksums from the candidate manifest with each report.

Use original, non-sensitive speech for a short unlocked recording. Require
**Recording is active**, evolving local transcript text, a completed Stop, and a
saved meeting under **Meetings**. Check its transcript, original notes and segment
playback. Missing models or pending cleanup are not a successful recording. After
model download, repeat with network access disabled to check the actual offline
path. Do not infer summary or Q&A support from the download button.

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

Finish any recording before renewal. Before the seven-day profile expires, use
the **same Apple Account and stable bundle IDs**, and install over the existing app. Do not delete the installed app
as part of normal renewal. Sideloadly documents this overwrite route and advises
backing up progress. Its automatic refresh requires the Windows PC/daemon to
run and the device to be detectable over USB or configured Wi-Fi. Manual USB
renewal remains the explicit fallback; unattended refresh has not been tested.
[Sideloadly renewal FAQ](https://sideloadly.io/faq.html)

Keep any exported real meeting backup local and private. Never attach recordings,
transcripts, Apple credentials, profiles or raw device logs to GitHub.

Before a manual refresh, preserve the existing installation and verify a usable
backup of anything important. A local Windows device backup is an additional
precaution: use iTunes **Summary → Back Up Now** and check its completion date.
[Apple Windows backup instructions](https://support.apple.com/en-ie/108967)

**Backup limitation:** LocalMinutes requests system-backup exclusion for its
private storage. A device backup is therefore not proof that its meetings/models
are recoverable. Current **Share text / Share Markdown** exports omit raw audio,
the database and model installations; full backup/restore export is unfinished.
Use disposable synthetic meetings for refresh tests until a complete backup
route has been verified. Keep original reference audio and exported text locally;
do not delete a good installation to work around a renewal problem.

For the preservation test, record the actual installed identifiers, synthetic
meeting title/note/transcript/audio duration, model revisions and expected hashes.
Renew in place, reopen that same meeting, compare its data/playback, and repeat a
short offline recording, Live Activity and Action Button test. Current screens
do not export full model/storage diagnostics; record unavailable evidence as
unavailable. Stable IDs and Sideloadly's overwrite guidance do not prove this
app's data preservation. Keep only a sanitized result in the repository.

## Owner-run endurance: two separate 125-minute passes

Begin only after a delivered candidate passes the short phone tests. Copy
[DEVICE_TEST_REPORT.md](templates/DEVICE_TEST_REPORT.md) for **each** pass; use the
same source/model versions or explicitly record any change.

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

**Locked ASR evidence remains unavailable:** a Live Activity timer or a transcript
seen after unlock cannot establish that recognition progressed while locked.
The candidate must supply processed-sample/timestamp/checkpoint evidence tied to
the locked interval, alongside owner observations. Redacted metrics/timeline
instrumentation is unfinished (T13). Mark absent measurements **NOT_AVAILABLE**
and the locked-live gate **UNVERIFIED**; neither long pass can be claimed from
the current UI alone.

Keep detailed evidence privately. A sanitized report can reference local evidence
hashes and the exact candidate; [VERIFICATION.md](VERIFICATION.md) is the index.
No actual endurance report has been produced by these instructions.

## Evidence still required

Free main-app and extension signing, actual installed identifiers, Live Activity
rendering and Stop control, Action Button warm and locked cold-start behavior,
phone-offline inference, live locked transcription, both 125-minute endurance
passes and renewal preservation all remain **NOT_RUN**. Test each separately.
If starting while locked requires unlocking, report that observed fallback
explicitly; only the owner can waive the desired cold-start experience.

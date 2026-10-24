# LocalMinutes MVP: install from Windows

Selected MVP source: `db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04`.
The final delivery message identifies the unsigned IPA, its SHA-256 checksum and
build manifest. On 24 October 2026 the owner reported successful installation with iLoader.
The exact installed build and tool version remain unrecorded.
You need Windows 11, an iPhone with iOS 18 or later, a USB cable and a free Apple
Account. No owned Mac, local Xcode or paid Apple Developer membership is needed.

## Install with iLoader

1. Download the Windows desktop release from [iLoader's official site](https://iloader.app/)
   or its [official repository](https://github.com/nab138/iloader). Follow the
   current Windows prerequisites, which list iTunes. Retain the setup that
   already worked for the owner's installation.

2. Download the delivered IPA, checksum and manifest. In Windows PowerShell,
   use `Get-FileHash -Algorithm SHA256` on the IPA and compare its checksum with
   the supplied file. Confirm the source in the manifest.

3. Connect and unlock the iPhone. Complete the computer-trust prompts in iTunes
   and on the phone. [Apple's trust instructions](https://support.apple.com/en-ie/109054)

4. Open iLoader, choose the phone and its custom IPA installation option, then
   select LocalMinutes. Handle free Apple Account sign-in and 2FA locally in
   iLoader. Retain the embedded Live Activity extension if asked. Keep the same
   signing account and installed bundle-ID settings for future renewals. Build
   IDs are `com.niranjankaruna.localminutes` and
   `com.niranjankaruna.localminutes.LiveActivity`.

5. Complete any developer-profile trust prompt under Settings → General →
   VPN & Device Management → the signing account. If required, enable Developer
   Mode under Settings → Privacy & Security, restart, unlock and confirm.
   [Apple's Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

## First launch and everyday use

Open LocalMinutes while unlocked. Go to **Models → Offline speech → Download
speech model** and wait for **Speech model verified**. The required English
model is approximately **73 MB**, downloaded separately from the IPA. Keep free
space for recordings. The optional 1.12 GB summary-model download is unnecessary
for this MVP; summary and Q&A app features are unfinished.

In **Record**, choose **Start Recording** and allow microphone access when
prompted. Handle any Live Activity permission/settings prompt on the phone.
Recording success requires **Recording is active** and evolving transcript
text. Use **Stop Recording** before leaving a meeting for playback or renewal.

Under **Meetings**, open saved meetings to read transcripts, edit original
notes, search the transcript, play a selected segment, or use **Share text /
Share Markdown**. Those shares send content to the destination you choose.
After installation and model download, local speech recognition requires no
cloud inference. Actual phone offline operation remains unverified.

## Renew every seven days without deleting the app

Before expiry, finish recording, reconnect the phone to Windows and use
**iLoader** to install over the existing app using the **same Apple Account and
the same actual installed bundle IDs**. Retain the identifier settings used by
the successful installation and keep the embedded extension. Manual USB
renewal is the project procedure; data preservation still needs verification.

Preserve the existing installation and locally export important text before
renewal. Data preservation for this app has **not** been verified. Text exports
omit audio and the database; private app storage requests backup exclusion, so a
device backup alone does not establish recovery. A complete backup/restore
feature is unfinished. Do not uninstall a good installation to resolve renewal.

**Owner-reported:** main-app installation with iLoader.
**Still unverified on the phone:** exact installed build and signing details,
embedded-extension installation,
Live Activity display/Stop, Action Button operation, locked continuation, locked
cold start, both long endurance passes, and renewal preservation. A timer or
transcript seen after unlocking does not prove recognition ran while locked.
The Action Button route is Settings → Action Button → Shortcut → a shortcut
containing **Toggle LocalMinutes Recording**; an unlock-required result remains
an explicit limitation. Optional observations belong in
[the device report](templates/DEVICE_TEST_REPORT.md). This is an MVP handoff,
not verified completion of those gates.

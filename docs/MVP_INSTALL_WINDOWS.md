# LocalMinutes MVP: install from Windows

Selected MVP source: `db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04`.
The final delivery message identifies the unsigned IPA, its SHA-256 checksum and
build manifest. This guide does not establish that installation has succeeded.
You need Windows 11, an iPhone with iOS 18 or later, a USB cable and a free Apple
Account. No owned Mac, local Xcode or paid Apple Developer membership is needed.

## Install

1. Download **Sideloadly for Windows** from [sideloadly.io](https://sideloadly.io/).
   Follow its links for the web editions of **iTunes and iCloud**; Sideloadly
   requires these instead of the Microsoft Store editions. Its official site
   supports free Apple Accounts and seven-day signing.

2. Download the delivered IPA, checksum and manifest. In Windows PowerShell,
   run `Get-FileHash -Algorithm SHA256` with the downloaded IPA's full path and
   compare the result with the supplied checksum. Confirm that the manifest
   names the source above.

3. Connect and unlock the iPhone. Complete the computer-trust prompts in iTunes
   and on the phone. [Apple's trust instructions](https://support.apple.com/en-ie/109054)

4. Open Sideloadly, choose the phone and IPA, and sign with your free Apple
   Account. Enter authentication and handle 2FA locally in Sideloadly. Leave
   **Remove Extensions/PlugIns off** so the Live Activity extension is retained.
   Keep the same bundle-ID settings for later renewals. The build IDs are
   `com.niranjankaruna.localminutes` and
   `com.niranjankaruna.localminutes.LiveActivity`.
   [Sideloadly features](https://sideloadly.io/)

5. If the phone reports an untrusted developer, follow Settings → General →
   VPN & Device Management → the signing account → Trust.
   [Sideloadly FAQ](https://sideloadly.io/faq.html)
   If Developer Mode is required, enable it under Settings → Privacy & Security,
   restart, unlock and confirm. [Apple's Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

## If Apple Account login fails with -80046

On 24 October 2026 the owner reported this error before installation.
[Other Sideloadly users report the exact code](https://github.com/SideloadlyiOS/Sideloadly-Download/issues/24).
The cause is unconfirmed; no working Sideloadly fix was established here.

Check that you can sign in at [Apple Account](https://account.apple.com/) and
complete any account prompts locally. Use the current release from
[Sideloadly's official site](https://sideloadly.io/) and retry once. If the same
error persists, signing remains blocked pending an upstream remedy. Keep any
existing LocalMinutes installation and the same Apple Account/bundle-ID
settings. Rebuilding the IPA does not address this login failure.

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

Before expiry, finish recording, reconnect the phone and sideload over the
existing installation using the **same Apple Account and the same installed
bundle IDs**. If Sideloadly rewrites an ID during first installation, keep that
same setting afterward. Automatic refresh needs the Windows daemon running and
the phone detectable; manual USB renewal is the fallback.
[Official renewal and overwrite guidance](https://sideloadly.io/faq.html)

Preserve the existing installation and locally export important text before
renewal. Data preservation for this app has **not** been verified. Text exports
omit audio and the database; private app storage requests backup exclusion, so a
device backup alone does not establish recovery. A complete backup/restore
feature is unfinished. Do not uninstall a good installation to resolve renewal.

**Still unverified on the phone:** free signing of the app and embedded extension,
Live Activity display/Stop, Action Button operation, locked continuation, locked
cold start, both long endurance passes, and renewal preservation. A timer or
transcript seen after unlocking does not prove recognition ran while locked.
The Action Button route is Settings → Action Button → Shortcut → a shortcut
containing **Toggle LocalMinutes Recording**; an unlock-required result remains
an explicit limitation. Optional observations belong in
[the device report](templates/DEVICE_TEST_REPORT.md). This is an MVP handoff,
not verified completion of those gates.

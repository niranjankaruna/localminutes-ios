# LocalMinutes on Windows: installation and seven-day renewal

Guidance checked against official sources on 23 October 2026. This procedure
has **not** been executed with LocalMinutes on the owner's phone. The project
does not yet have a delivered release candidate. Native compilation does not
prove free signing, extension installation, recording, or renewal preservation.

## Before installing a candidate

Use a candidate whose manifest names the exact tested source commit. Download
its unsigned IPA, SHA-256 file, build manifest and known limitations together.
Compare the IPA's SHA-256 with the supplied checksum before opening it in
Sideloadly; Windows PowerShell provides `Get-FileHash -Algorithm SHA256`.
Do not install a simulator app or a file from an unverified download source.
Model weights are installed separately in the app, after their integrity is
verified; they are not included in the normal IPA.

Record the phone model, iOS version, available storage and free-signing capacity
in local device evidence. Apple documents seven-day Personal Team provisioning
and limits on App IDs, registered devices and installed apps. The main app plus
embedded extension must be verified against the owner's actual capacity;
extension registration consumption has not been measured for this project.
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
   [Sideloadly features](https://sideloadly.io/),
   [Sideloadly changelog](https://sideloadly.io/changelog)

4. If iOS reports Untrusted Developer, Sideloadly's FAQ directs the owner to
   Settings → General → Profiles / VPN & Device Management → the signing
   account → Trust. Follow the actual free-development prompts shown on the
   phone. Apple's separate enterprise-app instructions are not evidence for
   this Personal Team flow.
   [Sideloadly FAQ](https://sideloadly.io/faq.html)

5. If required, enable Settings → Privacy & Security → Developer Mode, restart,
   unlock, confirm Enable and enter the phone passcode. Apple describes
   installing a development-signed app without Xcode as a way to expose this
   menu. No local Mac is required by this project's intended route; actual
   availability must be recorded on the owner's iOS version.
   [Apple Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device),
   [Apple explanation of installation without Xcode](https://developer.apple.com/videos/play/wwdc2022/110344/)

6. Launch LocalMinutes while unlocked and complete onboarding, microphone and
   Live Activity setup, verified model installation and first-unlock access.
   Do not treat a recording-only mode as successful live transcription.
   An app icon alone does not demonstrate that the embedded extension installed.

## Renew without deleting the app

Before the seven-day profile expires, use the **same Apple Account and stable
bundle IDs**, and install over the existing app. Do not delete the installed app
as part of normal renewal. Sideloadly documents this overwrite route and advises
backing up progress. Its automatic refresh requires the Windows PC/daemon to
run and the device to be detectable over USB or configured Wi-Fi. Manual USB
renewal remains the explicit fallback; unattended refresh has not been tested.
[Sideloadly renewal FAQ](https://sideloadly.io/faq.html)

Keep any exported real meeting backup local and private. Never attach recordings,
transcripts, Apple credentials, profiles or raw device logs to GitHub.

Renewal preservation is an acceptance test, not an assumption: record stable
installed identifiers, a synthetic meeting and installed-model hashes; renew
in place; then reopen the same meeting, compare its data and model hashes, and
check the Live Activity and Action Button again. Commit only a sanitized result.

## Evidence still required

Free main-app and extension signing, actual installed identifiers, Live Activity
rendering and Stop control, Action Button warm and locked cold-start behavior,
live locked transcription, two 125-minute endurance passes, offline real-model
inference and renewal preservation all remain **NOT_RUN**. Test each separately.
If starting while locked requires unlocking, report that observed fallback
explicitly; only the owner can waive the desired cold-start experience.

# T07: Sideloadly authentication failure, 24 October 2026

Checkpoint: 2026-10-24T14:52:02Z. Scope: diagnose the owner's screenshot.

The screenshot shows Login failed (-80046): This action cannot be completed
at this time. It establishes a failed Apple Account authentication attempt,
not signing, installation or extension registration. The selected IPA,
Sideloadly version, Anisette provider, Apple web sign-in result and actual phone
model/iOS are not established. No screenshot or raw account/device log is
copied into the repository.

Read on 24 October 2026:

- [Matching Sideloadly report](https://github.com/SideloadlyiOS/Sideloadly-Download/issues/24):
  open report from 21 October, with matching reports through 24 October.
- [AltStore issue 1840](https://github.com/altstoreio/AltStore/issues/1840):
  first-hand reports of the same code in another signing client.
- [Official Sideloadly changelog](https://sideloadly.io/changelog):
  authentication/Anisette changes, but no confirmed remedy for this exact code
  was found in the official pages checked. The site labels 0.71.0 latest while
  user reports mention 0.71.1; the owner's installed version is unknown.
- [Official FAQ](https://sideloadly.io/faq.html):
  app-specific passwords require a paid Developer account with Anisette
  disabled; this is not a verified free-account remedy.

A wider signing-client authentication problem is a plausible inference from
the matching reports. An Apple outage, account ban and exact Anisette cause
are unconfirmed. No recovery time or working free alternative is verified.
Apple's public status page returned no usable service-state text in this read.

T07 is BLOCKED_EXTERNAL with SIDELOADLY_APPLE_AUTH_80046. Overall project
remains IN_PROGRESS. Completed tasks in this troubleshooting invocation: none.
New tests/CI/commits/artifacts from this invocation: none. Existing source,
workflow and independent development checkpoints are preserved. Installed
apps, credentials, account settings and signing settings were not changed.

The GitHub connector independently rechecked the latest package
[run 40101392948](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40101392948):
completed/success, exact source d6a329354ffc095d4dffb9ca4d939c67bf10adc8.
This was compile/package only with zero tests; no signing/model/device pass.
Local gh authentication could not be validated and gh run list could not
connect to api.github.com. This does not establish that the stored token is
invalid. No credential retry or workflow dispatch was attempted here.

Next T07 action: the owner checks [Apple Account sign-in](https://account.apple.com/)
and completes any Apple prompts locally. Record only success/failure and
Sideloadly version/provider. If web sign-in succeeds, use the current official
Sideloadly release and retry once. Persistent -80046 remains blocked pending
an upstream remedy. Rebuilding the IPA does not address the observed sign-in
failure. Preserve any existing installation and account/bundle-ID settings.

All signing/extension, Action Button, locked live transcription, offline,
two 125-minute passes, renewal and file-protection gates remain unverified.
This screenshot does not change independent model-development authorization
or resolve the existing Qwen semantic-quality failures.

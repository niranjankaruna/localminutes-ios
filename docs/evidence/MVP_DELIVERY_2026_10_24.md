# LocalMinutes MVP delivery

The unsigned iPhone IPA is ready for Windows Sideloadly/free Apple Account signing.

- App source: db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04
- Build-only run: https://github.com/niranjankaruna/localminutes-ios/actions/runs/40092475736
- Workflow/checkpoint source: 3e25aae6117b9cad9d0251bded2f345b3155bdcf
- IPA: LocalMinutes-1.0-db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04-unsigned.ipa
- Size: 12632630 bytes
- SHA-256: 65d90c31a1109ee8291d1870b096dddb7cde1330962dd9e9ad8d557a5f96a70d
- iPhone arm64, iOS18+, app plus embedded Live Activity extension.
- Xcode26.2 / iOS SDK26.2.
- Local download hash matches both the runner manifest and GitHub asset digest.

Open MVP_INSTALL_WINDOWS.md for installation, first model download and weekly renewal. The required speech model downloads separately in the app (approximately73MB). No model weights, meeting data, credentials or signing files are included.

## Included MVP flows

Recording, actual local speech recognition, saved history, original manual notes, selected transcript search, segment playback and text/Markdown sharing. These are implemented in the selected source; the current delivery compiles/packages only and does not establish physical-phone behavior.

## Unfinished / unverified

Summaries and Q&A app screens/full model quality are unfinished. Full baseline onboarding/recovery/backup/accessibility/security work remains. Free signing of app+extension, Action Button warm/locked-cold start, locked live recognition, offline phone use, both owner125-minute passes, file protection and in-place renewal are NOT_RUN. Sign and install locally; no Apple credentials belong in chat or CI.

## Validation and pause

No new test runner executed for this delivery, as explicitly requested. App source previously passed full run40079629180 (269core,59Node,85TSAN,5actualQwen,59native,3UI,2product,13archive; physical7compile-only/0run). The current build-only workflow success does not convert those pending phone/full-baseline gates into passes.

Work pauses after this handoff at the owner's request. Later branch3e25aae contains unverified post-RED fixes excluded from this IPA. Resume only on explicit owner request.

Local delivered directory: `build/delivery/MVP-40092475736`.
Unpublished owner-only draft release:422706783, tagmvp-preview-db1b8d51c5ff; no public release published.

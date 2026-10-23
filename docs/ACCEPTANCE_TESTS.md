# Acceptance and release checklist

All entries start at NOT_RUN. This file defines tests; it does not supply results. Record actual evidence in `VERIFICATION.md` and individual reports. See the main specification for hard versus diagnostic performance thresholds.

| Gate | Requirement | Automated evidence | Required physical or account evidence |
|---|---|---|---|
| G01 | R01: repository first | Git history: initial specification commit before features | Correct authenticated owner/remote and visibility |
| G02 | R02: TDD | Meaningful RED then GREEN per behavior; exact CI SHA | None; test integrity review still required |
| G03 | R03: device artifact | iPhoneOS architecture, extension, plist, checksum, locked build | Free signing installs app and working extension |
| G04 | R04: recording | State/concurrency/permission/capture adapter tests | Real microphone start, truthful status, stop and playback |
| G05 | R05: locked ASR | Real-model fixtures, bounded streaming, metrics | Recognition progress during continuous locked operation |
| G06 | R06: controls | Intent idempotency, activity lifecycle, denial paths | App, shortcut, Action Button warm/cold, locked/unlocked, Stop |
| G07 | R07: endurance | Queue limits, simulated long timeline, failure injection | Two successful >=125-minute runs, >=120 minutes locked |
| G08 | R08: integrity | Partial replacement, timestamps, journal, migration, recovery | Playback and transcript aligned; interruptions marked |
| G09 | R09: offline/model integrity | Hash/import/cancellation and network-path tests | Recording, ASR, summary and Q&A offline after setup |
| G10 | R10: intelligence | Real model, schema/evidence, missing owners/dates, isolation | Semantic review on fixed non-sensitive cases |
| G11 | R11: renewal | Stable IDs; schema and data-preserving upgrade tests | In-place free-account renewal preserves records/models/settings |
| G12 | R12: usability/privacy | UI/a11y, redaction, no fake adapters, dependency/license checks | Owner walkthrough, privacy controls and complete install guide |

## Minimum negative and regression cases

Test duplicate/concurrent starts, repeated stops, cancellation while preparing, denied microphone, disabled Live Activities, reboot-before-first-unlock, corrupt/missing model, disk-full during segment rotation, recognizer overload, audio route/sample-rate change, microphone interruption, audio-service reset, active model deletion, crash before/after checkpoint, backgrounding during summary, malformed generated JSON, invalid evidence IDs, cross-meeting search leakage, spoken prompt injection, and no network after setup.

A general fallback must not turn a failed core requirement into a pass. In particular, recording-only or post-unlock ASR fails G05/G07 for live behavior. An unlock-required cold start must be disclosed in G06 and approved by the owner if it changes the desired experience.

## Endurance evidence rules

Test on the actual target device without a Mac/debugger attachment being required. Use non-sensitive external speech. Log source/model hashes, environment, sample progress, recognition progress while locked, latency, backlog, memory, thermal and battery observations. Do not infer progress from transcript text appearing after unlocking. Record real gaps; never splice them away to make a clean result.

The hard gates include no sustained backlog growth, p95 partial latency <=5 seconds, p95 backlog <=5 seconds, no unreported interval over 15 seconds, and <=50 MiB steady-state memory growth between minutes 30 and 120. Capture must last at least 120 minutes. A 125-minute test and two successful long runs provide margin. Test disruptions separately from clean endurance. All thresholds are proposed targets, not existing measurements.

## Final review

Check source SHA and dependency/model compatibility of every device report. A changed audio runtime may invalidate an older endurance pass. No unchecked boxes, skipped mandatory tests, uncommitted production changes, missing checksum, fake inference, hardcoded secrets, or unresolved critical blockers may be hidden in a completion claim.

If all code passes but the owner has not run device tests, use CODE_COMPLETE_PENDING_DEVICE, not VERIFIED_COMPLETE.

# Repository consolidation â€” 25 October 2026

Scope: owner requested merging all branch work into `main`, retaining only
`main`, adding a README, and removing obsolete or unused repository material.
This is maintenance; no application behavior, model selection, or acceptance
criterion is changed. No new native build or model-quality benchmark is needed
to establish this documentation and path-only change.

## Branch inventory and preservation

Verified repository: `https://github.com/niranjankaruna/localminutes-ios`.
Authenticated owner/admin: `niranjankaruna`. Existing visibility is public under
the recorded publication approval; visibility was not changed. Git identity
was already configured. The working tree was clean before consolidation.

After fetching origin, local and remote branch heads agreed:

| Branch | Original tip |
| --- | --- |
| `main` | `db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` |
| `task/t02-harness` | `abaf4387ed3bdb84c7218a7ef93e2dd80811c010` |
| `task/t03-recording-coordinator` | `809f653c8b3cb52c1c04943401eb42d166d7e94b` |
| `task/t04-ios-build` | `ca803757573b5f98ff502494f5526b1db620b7d5` |
| `task/t05-capture` | `a1f8a4ae5f7911dc10ccf1892ee9f134173d169f` |
| `task/t06-activity` | `a314967626b01b0a3a071eb61eb02b2d5d2320e8` |

`main` was exactly 75 commits behind `task/t06-activity`, with no divergent
commits. All other branch tips were ancestors of that latest tip.
`git switch main` and `git merge --ff-only task/t06-activity` preserved every
commit, including test-first history. `git merge-base --is-ancestor` succeeded
for every fetched local/remote ref against consolidated main.
No rebase, squash, force push, repository recreation, or visibility change.

Remote verification completed at 2026-10-25T13:44:29Z. Cleanup commit
`eeb9a5dc65a06ef11142c449e4a5e3170500eb69` was pushed normally to `main`. Remote main was independently
verified at that exact SHA before deletion. Every advertised remote tip was
again checked for ancestry before `git push origin --delete` removed all five
task branches. All five merged local branches were removed with `git branch -d`.
After fetch/prune, `git ls-remote --heads origin` returned only `refs/heads/main`,
at the same SHA as local main; `git status --porcelain=v1` was empty.
No unmerged commit was discarded. This separate documentation checkpoint
records the completed operation; the current HEAD is available from Git.

## Cleanup

- Added a root README and documentation index describing the actual delivered
  app, Windows workflow, repository layout, and pending phone acceptance.
- Replaced superseded model/library instructions with current `MODELS.md` and
  `LIBRARY.md`; updated summary usage and current navigation.
- Removed 122 retired uncompiled draft files, eight obsolete documents
  (three bootstrap prompts, the duplicate Word specification, and four old
  model/MVP/install guides), and three ignored Python bytecode cache files.
- Relocated all five live fixture helpers from `docs/drafts/T10` and `T17` to
  `scripts/fixtures`. Updated workflow calls and the summary-to-Whisper helper
  path; sibling imports replace the obsolete draft-directory import lookup.
  The three jobs supporting historical checkouts select the single tracked
  helper from that revision, preserving older paths during historical replay.
  Native preparation algorithms, pins, checksums, and downloaded-byte policies
  remain unchanged.
- Compacted repeated state/progress/verification/blocker snapshots and removed
  obsolete active-CI and next-action claims. Every backlog task ID, acceptance
  criterion, dependency, status, and device evidence is retained. Historical
  snapshots and removed files remain reachable at commit `a314967` in Git.
- Preserved application code, all active tests, dedicated TDD and quality
  evidence, dependency receipts, privacy rules, and ignored local deliveries.

## Actual checks

Baseline at `a314967`: `node --test scripts/tests/*.test.mjs`, Windows 11 /
Node 24.21.0: **62 passed, 0 failed, 0 skipped**. A sandboxed attempt was denied
temporary symlink creation; the normal-filesystem run passed. That permission
failure is not a behavioral RED.

Post-cleanup at commit `eeb9a5dc65a06ef11142c449e4a5e3170500eb69`:

| Check | Actual result |
| --- | --- |
| `node --test scripts/tests/*.test.mjs` | 62 passed, 0 failed, 0 skipped; Windows 11 / Node 24.21.0 |
| Protected source/test byte comparison | All 219 protected files unchanged, including all 111 files under Tests |
| Relocated Python helpers | Five syntax-tree comparisons and imports passed on Python 3.12.14; no downloads invoked |
| Workflow references | Current helper paths exist; historical helper selection resolves in all three pinned revisions |
| Documentation and metadata | 163 relative Markdown links resolve; JSON parses; no whitespace errors |
| Backlog and device contracts | Every prior task/status/acceptance/dependency/device-evidence field unchanged |
| Branch ancestry | Every original local/remote tip reachable from main |
| Existing ignored build 6 IPA | SHA-256 still matches `08c00c22c0edd446ec0656a5695d9b05e20b7d1cc497f9186f57ec99cf00f2e0` |

The remaining checkpoint changes update documentation/status and pin Python
source line endings to LF. They do not change the tested scripts or app sources.
The maintenance audit compares all application/test bytes with the original
snapshot, compares relocated Python syntax trees after path substitutions,
imports the helpers without invoking downloads, checks every workflow helper,
checks local documentation links and JSON, preserves backlog/device contracts,
and verifies ancestry for the original branch tips.

Latest existing relevant CI was read from GitHub: focused run `40193408469`,
source `81fbff3a1bdf4ed17b757dd96d97486d9485254f`, terminal SUCCESS.
Original run `40190643613` remains FAILURE; its composite passing groups are
scoped in the [requirement handoff](MVP4_REQUIREMENT_HANDOFF.md).
No new CI was dispatched for maintenance. These checks are not an iOS build,
an inference/quality result, or a physical-device validation.

## Remaining acceptance and next task

Maintenance task: `REPO_CLEANUP` is `VERIFIED_COMPLETE`. Application task `T23` remains blocked on
`OWNER_PHONE_VALIDATION_REQUIRED`; no device result is changed from `NOT_RUN`.
The delivered build remains `READY_FOR_DEVICE_VALIDATION`, and the full project
remains `BLOCKED_EXTERNAL` with `verifiedComplete: false`.

Next: owner records installed build 6 and a short recording saved by Live
Activity Stop, then completes [the phone checklist](../MVP4_DEVICE_CHECKLIST.md):
chosen models offline, Action Button warm/locked/cold-start, two 125-minute
passes with at least 120 locked minutes each, storage protection, and in-place
renewal preservation. Reproducible defects can reopen code work.

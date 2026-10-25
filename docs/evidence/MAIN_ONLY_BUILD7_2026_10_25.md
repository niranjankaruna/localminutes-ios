# Main-only branch cleanup after build 7

Owner request, 25 October 2026: keep only main and remove the other branches.
Task `BRANCH_CLEANUP_BUILD7` is `VERIFIED_COMPLETE` for repository maintenance;
the application remains `READY_FOR_DEVICE_VALIDATION`.

## Preserved work

The working tree was clean. Fresh local and origin inventories each contained
only `main` and `codex/parakeet-downloads`. GitHub authentication resolved the
configured owner `niranjankaruna`, repository `niranjankaruna/localminutes-ios`,
with `main` already the default branch. The existing Git identity was retained.
The only checkout was this workspace; no other worktree was affected.

| Reference before consolidation | Verified SHA |
| --- | --- |
| Local/origin main | `ac26bec9ed68503371cce061a6e9d4d615f4bae5` |
| Local/origin task branch | `170699886370fb28819d0d302a191519a7964de6` |
| Delivered build 7 application | `6c02ccdd911017a613de2052e5fee1e611b953f7` |

Ancestry checks showed main was an ancestor of the task branch, with nine commits
to preserve. `git merge --ff-only codex/parakeet-downloads` moved main to
`1706998`; pushing main succeeded. Both origin heads then pointed to that exact
commit. The remote task branch was deleted, followed by local `git branch -d`.
After pruning, local and remote branch inventories contained only main. The
normal `origin/HEAD` symbolic alias still points to `origin/main`.

No squash, rebase or force push was used. All test-first commits and their CI
history remain reachable through main. This following checkpoint updates only
documentation; it is pushed and compared with the remote separately.

## Verification and delivery scope

- Git ancestry and fresh local/remote reference comparisons passed.
- Diff against the delivered application source is zero for application,
  runtime, resource, project, workflow and test files.
- Latest relevant [native CI 40220308515](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40220308515)
  was re-read: completed/SUCCESS at the delivered application SHA.
- The existing build 7 IPA remains unchanged, SHA-256
  `4adfea3a38463b69423d58e4d8f1b2434f65ceeb2483e091eb26a0987ec0f967`.
- No new tests, CI run, IPA build or physical-phone result was created. This is
  reference/documentation maintenance, so behavior-change TDD does not apply.

The [build 7 guide](../MODEL_UPGRADE_BUILD7.md), artifact and model data are
preserved. All phone inference, Live Activity/Action Button, locked/endurance,
file-protection, free signing and renewal gates remain pending. Next: the owner
installs and validates build 7 using the model and physical-device checklists.

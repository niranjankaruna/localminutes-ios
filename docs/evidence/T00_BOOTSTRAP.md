# T00 repository bootstrap evidence

Observed: 23 October 2026, approximately 15:40 Europe/Dublin (14:40 UTC).
Requirement: R01. Documentation/account observation; no product behavior changed.

- The selected Localminutes folder contained only the 19 supplied specification,
  hygiene and state files. Git reported no repository or parent repository.
- Existing Git author identity was present. No identity was fabricated or changed.
- `gh auth status` and `gh api user --jq .login` succeeded outside the restricted
  network sandbox. Authenticated login: `niranjankaruna`; HTTPS Git operations.
  The sandbox initially gave a misleading invalid-login/connectivity result;
  the direct check resolved it. No reauthentication or credentials were collected.
- `gh repo view niranjankaruna/localminutes-ios` found no repository before creation.
  `gh repo create niranjankaruna/localminutes-ios --private` created the empty remote.
  A subsequent metadata query returned `PRIVATE`, the expected owner/name and URL.
- A bounded independent agent reviewed all 19 supplied files, including the DOCX
  package structure, metadata and relationships. No credential patterns, sensitive
  artifacts or unsupported success claims were found. DOCX layout was not evaluated.
- Explicit staging included only those 19 files. `git diff --cached --check` passed.
- Initial commit: `5767409b9bc8797a53409bc4bd86799019c833b4`, subject
  `chore: initialize LocalMinutes specification and execution contract`.
- `origin`: `https://github.com/niranjankaruna/localminutes-ios.git`.
- `git push -u origin main` succeeded. `git rev-parse HEAD` and
  `git ls-remote origin refs/heads/main` returned the same full SHA above.
- `gh run list --repo niranjankaruna/localminutes-ios --branch main` returned `[]`.
  No CI, app build, test, signed artifact or device result existed at bootstrap.

The repository URL and bootstrap SHA are recorded in a subsequent documentation
commit, not claimed to have existed in the initial commit itself.

Next: T01 environment/cost/toolchain verification, then T02 harness RED/GREEN.

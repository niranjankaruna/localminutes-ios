# Start here

This package is an autonomous-development brief for **LocalMinutes**, not a finished application. No GitHub repository, application source, IPA, or device test has been created by this package.

## Use in your local project
1. Extract the **contents** of this package into your intended local project root. Keep `AGENTS.md` at that root, not inside a nested folder. Preserve existing files rather than overwriting unrelated work.
2. Open the project in your coding agent. Ensure Git and GitHub CLI are installed and that `gh auth status` succeeds using your own account. Never paste an Apple/GitHub password into an AI prompt.
3. Paste the contents of `START_PROMPT.md` as the goal. For later sessions, use `RESUME_PROMPT.md`.

The first development operation is to create the GitHub repository, initialize/preserve local Git as appropriate, make the initial documentation commit, and push it. All application behavior then follows tests-first development.

## Files to know
| File | Purpose |
|---|---|
| `AGENTS.md` | Instructions the coding agent must reread each run |
| `docs/IMPLEMENTATION_GOAL.md` | Authoritative complete technical and execution specification |
| `docs/IMPLEMENTATION_GOAL.docx` | Human-readable Word copy of the same specification |
| `project-config.json` | Cost, visibility, retry, and device defaults |
| `docs/BACKLOG.json` | Ordered work and dependency graph |
| `docs/STATE.json` | Current checkpoint; starts honestly at NOT_STARTED |
| `docs/ACCEPTANCE_TESTS.md` | Automated and physical-device release gates |
| `docs/PROGRESS.md`, `BLOCKERS.md`, `DECISIONS.md`, `VERIFICATION.md` | Persistent history and evidence |
| `docs/templates/` | TDD evidence and physical-device report templates |

## One choice affecting free CI
The default repository is **private** to prevent accidental publication. Private repositories have finite included GitHub Actions allowances. The agent must verify that billed overage is blocked before metered CI starts. Standard public-repository runners are free, but making the repository public needs your explicit permission. The package therefore does not silently select public visibility or promise unlimited private CI. See source references S8 and S9 in the specification.

To authorize a public repository before creation, explicitly set `github.visibility` to `public` and `github.publicationApproved` to `true` in `project-config.json`, after reviewing all material that will be published. Leave both at their defaults otherwise. Do not set `ci.costGuardVerified` to true merely to bypass a check: it requires actual account-level evidence.

## Human actions that remain
You own account sign-in, approval of necessary workstation installations, Apple authentication/2FA, iPhone trust/Developer Mode and microphone permission, Action Button assignment, sideloading, and real-device tests. A coding agent cannot prove two-hour locked recording from a simulator or a written plan.

The agent should continue independent work while a device gate is pending. It must stop rather than repeatedly retry missing credentials, spend money, or falsely declare completion. The prompts do not launch an unlimited autonomous background service; your coding environment controls execution and resumes.

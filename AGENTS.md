# Repository rules

## Branch policy

- Work only on the `main` branch.
- Do not create any other local or remote branch, including temporary, feature, or validation branches.
- Do not switch to another branch or create a worktree backed by another branch.

## GitHub workflows and Actions

- Do not create GitHub workflows unless the user explicitly asks for them.
- Do not run, dispatch, or rerun GitHub Actions unless the user explicitly asks to run them.
- Do not indirectly trigger GitHub Actions through pushes or other operations without that explicit authorization.
- Implementation, build, or testing requests do not by themselves authorize GitHub Actions or verification on GitHub-hosted macOS runners.

## Implementation quality

- Implement changes with the highest accuracy possible, grounded in the actual repository code and requirements.
- Consult authoritative documentation, real implementation examples, and relevant release notes when choosing or changing APIs and behavior.
- Prefer official documentation and maintainer-provided examples. Check compatibility with the project's actual dependency versions and supported platforms.
- Do not invent APIs or present assumptions as verified facts. Clearly identify uncertainty, limitations, and any validation that has not been performed.

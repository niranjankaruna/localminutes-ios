# Public repository approval and cost guard

On23October2026 the owner explicitly instructed this chat: "If you need more
build minutes, change the repository to public. We will get unlimited build
minutes." This authorizes publishing niranjankaruna/localminutes-ios. It
supersedes the original private default for this repository only. No other
repository, credentials, private meeting data or billing setting is authorized.
project-config.json now records public visibility and publicationApproved:true.

The private allowance was nearly exhausted: the latest read-only observation
showed1,811.3/2,000 included Actions minutes used before the final native job's
charge settled, Actionsbillable$0, storage0.5/0.5GB100%. The existing account-wide
Actions$0/$0 Usageblocked guard was separately verified before run6. No billing
settings were changed.

GitHub's official
[standard-runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job#standard-github-hosted-runners-for-public-repositories)
states standard hosted runners are free and unlimited for public repositories,
and includes the actual macos-15-intel label used here. The
[billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
separately excludes larger runners from that free use. Keep standard runners,
bounded jobs, one active run per branch, six new runs per invocation and no
automatic recursive sessions. Public visibility does not waive device or TDD
acceptance, artifact retention verification, or the zero-spend requirement.

Before visibility change, reviewed all reachable local/remote-tracking history:
56commits,804objects,416blobs,128historical paths. A local read-only scan found
zero credential-signature matches and zero forbidden media/model/database/
signing/local-evidence paths. It also inspected historical DOCX XML. The sole
binary member, its blank thumbnail, was visually inspected; document author
metadata is empty, custom bibliography empty, external links are public primary
sources. No embedded meeting data was found. This is a scoped review, not a
claim that automated scanning can prove the absence of every possible secret.

Repository secret/variable listings were empty; retained Actions artifacts0,
issues/PRs0, releases0. Workflow review found pinned standard checkout,
persist-credentials:false, contents:read permissions, no secret-reference,
pull_request_target or upload path. Actual CI outputs use synthetic/non-sensitive
fixtures; no meeting/device raw logs are committed. The local audit report is
ignored at.agent-local/publication-review.json; it prints paths/signature types,
never secret values. No unrelated repository or account data was published.

Visibility change verified23October2026 at21:59:27UTC. Authenticated repository
query returned nameWithOwner:niranjankaruna/localminutes-ios, visibility:PUBLIC,
isPrivate:false, defaultBranch:main. An independent unauthenticated request to
https://api.github.com/repos/niranjankaruna/localminutes-ios also returned
private:false and visibility:public. Repository:
[LocalMinutes](https://github.com/niranjankaruna/localminutes-ios).
The web search fetch cache had no fresh entry; the live GitHub API checks above
are the evidence, not that failed cached fetch.

No CI run was dispatched by the visibility change. Continuation-05 has already
used its6/6 permitted runs. The covered cancellation repair is committed locally
at695b99ba9857488ec759bf3b723feb73f734b3b8. Restore the native job's prior bounded
25minute allowance for the next invocation; the15minute private-budget cap
interrupted the UI suite after one real passing case. Keep every assertion,
result-bundle check, regression and failed exit mandatory. Core remains6minutes,
both below the45minute per-job maximum. No larger runner, purchase, upload or
spending-guard change is introduced. Artifact retention remains separately
unverified; making a repository public alone does not prove IPA delivery.

# T01 environment observations

Observed: 23 October 2026, approximately 15:41 Europe/Dublin (14:41 UTC).
Requirements: R01, R03. These are account/documentation observations, not an iOS build.

## Workstation

Windows workstation; PowerShell 7.6.5 reports Microsoft Windows 10.0.26300,
Win32NT. Git 2.55.0.windows.5, GitHub CLI 2.102.0 and Node.js v24.21.0 execute.
`swift` is not on PATH. The Python entries on PATH are WindowsApps aliases;
Python execution was not verified. Xcode/iOS compilation has not run locally.
An optional OS CIM query was denied by the sandbox; it is not a build blocker.

## CI cost observation

Read-only browser inspection of the signed-in `niranjankaruna` personal account:

- [Billing overview](https://github.com/settings/billing) showed GitHub Free.
- The Actions tab showed **127 minutes used / 2,000 included**, leaving 1,873
  displayed included minutes, with reset in 9 days.
- Actions billable usage was **$0**, consumed usage $0.89 fully discounted $0.89.
- Actions storage showed **0.5 GB used / 0.5 GB included** (rounded UI values).
  Artifact headroom is not established; initial tests will use logs without uploads.
- [Budgets and alerts](https://github.com/settings/billing/budgets) showed an
  account-wide Actions budget **$0.00 / $0.00 spent**, status **Usage blocked**.
  This existing hard stop is the no-overage guard; no billing setting was changed.

The CLI billing usage endpoint returned HTTP 404 and reported missing `user`
scope. No scope refresh was attempted; the authenticated browser supplied the
account evidence instead. This is not a remaining authentication blocker.

This observation authorizes only bounded standard-runner use within included
allowance. Recheck remaining usage before native builds or a later invocation;
never infer artifact headroom from compute allowance. Maximum six new runs in
this invocation, one active per branch, jobs no longer than 45 minutes, and
one-day retention for any later artifacts. Logs/job summaries do not consume
artifact allowance according to GitHub's billing documentation.

Sources checked 23 October 2026:

- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [Hard budgets](https://docs.github.com/en/billing/how-tos/set-up-budgets)
- [Standard hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## Toolchain

Selected standard runner: `macos-15-intel`, Xcode **26.2 / 17C52** at
`/Applications/Xcode_26.2.app`. The official runner README at revision
`07cc2190cd4d100d9f69478219017720c02c40f6` lists this Xcode and image
`20260824.0482.1` (macOS 15.7.9). This is the documented selection, not an
observed runner execution; CI must log actual image/Xcode/Swift/SDK values.

Checkout action selected: **v7.0.1**, immutable commit
`3d3c42e5aac5ba805825da76410c181273ba90b1` resolved from its official tag.
Its `action.yml` was inspected; it uses node24. Builds will request only
`contents: read` and set `persist-credentials: false`. No community setup action
is needed to select the already installed Xcode.

XcodeGen **2.46.0** is the current official release observed via the publisher's
release metadata. Its source/artifact hash and installation need validation in
T04; it has not been installed. No native dependency or model is pinned yet.

Sources:

- [Runner image at reviewed revision](https://github.com/actions/runner-images/blob/07cc2190cd4d100d9f69478219017720c02c40f6/images/macos/macos-15-Readme.md)
- [Checkout action at reviewed revision](https://github.com/actions/checkout/blob/3d3c42e5aac5ba805825da76410c181273ba90b1/action.yml)
- [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)

T01 changes are documentation/configuration of observed account facts only;
no executable script or application behavior was implemented. T02 establishes
the actual harness under the explicitly permitted harness bootstrap exception.

## Actual hosted toolchain observation

Run [39972652907](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39972652907)
at source `ef311b97ed475f9cecec61805f7020ca23a4382f` logged macOS 15.7.9 / 24G830,
image `20260824.0482.1`, x86_64, Xcode **26.2 / 17C52**, Apple Swift **6.2.3**
(`swiftlang-6.2.3.3.21`, clang `1700.6.3.2`), target x86_64-apple-macosx15.0,
and iPhoneOS/iPhoneSimulator SDK **26.2**. It enumerated available simulators;
no simulator tests or device build ran. The package compiled and executed two
XCTest cases. This verifies the hosted selection, not an iOS application.

## Storage follow-up before artifact work

At approximately 16:07 Europe/Dublin, a second read-only account observation
showed **199.3 / 2,000 minutes used**, billable **$0**, and storage still
**0.5 / 0.5 GB**. The rendered storage progress indicator was **100%**.
No artifact capacity is established. Build/testing without uploads may continue;
IPA delivery must wait for verified included-storage headroom. The owner may
need to remove their unneeded artifacts or wait for expiration; this run does
not delete unrelated account data or change billing.

## Continuation cost recheck — 23 October 2026, approximately 16:25 Europe/Dublin

Read-only authenticated account inspection again showed GitHub Free,
**261.3 / 2,000 included Actions minutes used** (1,738.7 displayed remaining),
billable Actions usage **$0**, storage **0.5 / 0.5 GB**, and the account-wide
Actions budget **$0.00 / $0.00, Usage blocked**. No account setting was changed.
The invocation may use at most six standard-runner runs. The earlier planning
estimate of 1,500 weighted minutes assumed a tenfold multiplier; current pricing
documentation does not establish that exact multiplier, so it is not a verified
upper bound. Three initial core-only runs are now complete; the remaining three
planned runs have a combined core/native timeout of 25 runner minutes each.
The observed allowance and enforced $0 stop permit bounded standard-runner
execution; recheck account usage before another invocation. No unlimited free
macOS allowance is assumed.
Artifact uploads remain blocked on headroom verification; logs-only tests and
native builds may proceed. Existing runner/action pins remain unchanged.

## Continuation-02 cost observation — 23 October 2026

Read-only authenticated account inspection showed GitHub Free, **457.7 / 2,000
Actions minutes used**, 1,542.3 displayed remaining, Actions billable usage **$0**,
and account-wide Actions budget **$0.00 / $0.00, Usage blocked**. Included storage
still displayed **0.5 / 0.5 GB, 100%**, so artifact upload remains blocked. No
settings or unrelated artifacts were changed. Bounded standard-runner execution
may resume; start with the saved native packaging fix. Maximum six new runs,
one active run per branch, existing 10-minute core / 15-minute native timeouts.
Do not assume the entire remaining allowance is reserved for this project.

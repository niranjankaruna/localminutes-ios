# Pristine native product validation — regression evidence

The existing mandatory native archive test is an actual failing regression at
`8b653cb8c33b7abd2d83e747b7bc404d1900f5f5`,
[run40077503748](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40077503748),
native job120823956500. It executes on real hosted macOS/Xcode26.2 products:
13 archive cases, 12 passed, one failed, zero skipped. The actual device positive
IPA/CRC/hash/source case passed; the negative Simulator case expected a platform
rejection, but its reused Debug product had already been instrumented and signed
by XCTest. The input tree correctly rejected signing material first. No test or
package/privacy/signature/platform assertion may be weakened to hide that result.

Earlier source39d9eaa's separate strict product inspection similarly observed an
embedded XCTest bundle after tests. That inspection was moved before instrumented
execution and now passes both cases. The archive suite's Simulator fixture also
needs the pristine product. This is the second bounded ordering repair, after
actual new assertion evidence, not a third blind retry or a build/tool failure.

Repair: move the unchanged full13-case archive suite immediately after pristine
product inspection, before physical build-for-testing and Simulator installation.
Keep the final standalone ephemeral IPA creation after every native/UI assertion.
All three workflow jobs remain mandatory. No product mutation, test-bundle
deletion, signature removal, assertion rebaseline, upload, release or billing
change is introduced. Native job remains bounded at35minutes, below45.

GREEN exact source/run/counts: PENDING sixth and final allowed CI run. All other
source8b653cb groups passed:269core,59Node,85TSAN,5actualmodel,59native,3UI,2native
bundle checks; zero skips/reported races, native/UI result bundles agree.
Physical7 compiled, zero executed/NOT_RUN. No retained candidate exists.

Next: require all13 archive cases plus full regressions GREEN at the exact new
SHA, then checkpoint without dispatching run7. T12 interruption drafts remain
inactive/uncompiled with no behavioral implementation before their future RED.

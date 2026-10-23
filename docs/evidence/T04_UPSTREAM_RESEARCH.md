# T04 upstream research only

23 October 2026. A bounded read-only reviewer checked official upstream sources.
No LocalMinutes iOS target, dependency installation, device build, IPA or signing
result is supplied by this document. T04 remains NOT_STARTED.

XcodeGen release **2.46.0**, source tag commit
`8445e778451c7e44237b90281bde622d764b0084`.
Official release API reports `xcodegen.zip` asset ID `478866069`, 4,278,764 bytes,
publisher SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`.
These are publisher metadata, not an independently hashed downloaded binary.
Preserve `xcodegen/bin/xcodegen` alongside its `share/xcodegen/SettingPresets`.
Upstream CI includes Xcode 26.2; actual LocalMinutes compatibility still needs a build.

The project specification documents application and app-extension target types,
iOS platform/deployment settings, explicit stable bundle identifiers, shared
ActivityAttributes sources, application dependency embedding the extension, and
a shared app scheme. App plist needs Live Activities support; extension uses
`com.apple.widgetkit-extension`. Recording permission/background configuration,
Live Activity controls and real adapter behavior still require tests first.

Sources:

- [Official release](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)
- [Release metadata](https://api.github.com/repos/yonaskolb/XcodeGen/releases/tags/2.46.0)
- [Pinned project specification](https://github.com/yonaskolb/XcodeGen/blob/8445e778451c7e44237b90281bde622d764b0084/Docs/ProjectSpec.md)
- [Pinned archive script](https://github.com/yonaskolb/XcodeGen/blob/8445e778451c7e44237b90281bde622d764b0084/scripts/archive.sh)
- [Live Activity APIs](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

Next T04 action after T03: write failing native project/package validation tests,
obtain meaningful RED with minimal compiling stubs, then implement/build and
verify device and simulator products. Check artifact storage headroom before
uploading anything. AudioRecordingIntent SDK declarations and free signing must
be checked in their dedicated early gates; documentation is not device evidence.

# LocalMinutes identity

[Open the combined logo and splash preview](./local-minutes-preview.png).

An original audio-to-notes mark: rounded audio pulses resolve into three lines of meeting minutes. Blue follows the existing app's accent; the light and dark splash backgrounds match its semantic colors.

## Assets

- [1024px square icon](./local-minutes/local-minutes.png) and [editable SVG](./local-minutes/local-minutes.svg). The square export has an opaque background and no baked corner mask.
- [Rounded icon preview](./local-minutes/local-minutes.preview.png), with reusable foreground and background layers in [layers](./local-minutes/layers/).
- [Transparent logos](./logo/): blue, white, and ink symbols; light and dark horizontal wordmarks. Every asset has SVG and PNG versions.
- [Light splash](./splash/local-minutes-splash-light.png) and [dark splash](./splash/local-minutes-splash-dark.png): 1179 x 2556 PNG exports with SVG equivalents using a 393 x 852 logical canvas.

The phone hardware, status bar, and home indicator appear only in the combined presentation. The standalone splash files contain only the artwork. Typography is outlined in the delivered SVGs to avoid font substitution; live-text SVG sources are retained under [editable-svg](./local-minutes/tmp/work/editable-svg/). Windows previews use Segoe UI; native app implementation should retain the app's system typography and adapt layout to the actual screen.

Target context: iOS 18 and later. The approved icon and splash are integrated through [BrandAssets.xcassets](../../Resources/BrandAssets.xcassets/), [LaunchScreen.storyboard](../../Resources/LaunchScreen.storyboard), and the app target in [project.yml](../../project.yml). The asset catalog supplies a single 1024px RGB app icon, a transparent template mark at 1x/2x/3x, and adaptive light/dark colors. The storyboard uses native system text and Auto Layout; iOS controls the launch duration. App startup has no added timer or loading gate.

These checked-in native resources require no design tools at build time. The original SVG/PNG sources remain in this folder. No Icon Composer package is needed for this asset-catalog integration. The presentation uses Segoe UI, while the native launch screen uses the iPhone system font.

Local validation checks the asset metadata, image dimensions, icon opacity and pixel fidelity, template rendering, and storyboard references. Native asset compilation and launch rendering require Xcode on macOS and have not been run from this Windows workspace.

## Regenerate

The [design specification](./local-minutes/tmp/work/semantic-icon-design.json), [icon spec](./local-minutes/tmp/work/spec.json), and [artwork generator](./local-minutes/tmp/work/build-brand-assets.mjs) preserve the design. The generator uses the installed app-icon-gen skill's locked Node dependencies. Set `APP_ICON_SKILL_SCRIPTS` if that skill is installed elsewhere.

From the repository root, prepare the current spec:

```powershell
node Design/Brand/local-minutes/tmp/work/build-brand-assets.mjs prepare
```

Run the skill's `author-icon` with absolute `--spec` and `--out` paths. On Windows, the [compatibility helper](./local-minutes/tmp/work/prepare-windows-author.mjs) creates a local copy that corrects the tool's slash-only path-depth check, preserving its root, ownership, symlink, and containment guards. It leaves the installed skill unchanged.

```powershell
node Design/Brand/local-minutes/tmp/work/prepare-windows-author.mjs
```

Then run `npm --prefix Design/Brand/local-minutes/tmp/work/icon-tooling run author-icon -- --spec ABSOLUTE_SPEC_PATH --out ABSOLUTE_DELIVERY_PATH`, followed by:

```powershell
node Design/Brand/local-minutes/tmp/work/build-brand-assets.mjs export
```

After changing the approved icon source or semantic layers, regenerate the native asset catalog:

```powershell
node Design/Brand/local-minutes/tmp/work/export-ios-assets.mjs
```

Review the regenerated icon at full size and 64px, inspect both splash appearances, record a fresh visual review, then run the skill's `verify` command against the delivery directory. Generation invalidates the previous review evidence.

Apple references: [app icons in an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) and [native launch screen configuration](https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen).

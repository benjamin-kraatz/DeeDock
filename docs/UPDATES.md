# Publish a DeeDock update

Use the `DeeDock` scheme for direct distribution. Its resources include the unchanged third-party notices from `ThirdParty/Sparkle-LICENSE.txt`. It includes Sparkle 2.9.6 and uses the public GitHub Releases feed:

`https://github.com/benjamin-kraatz/DeeDock/releases/latest/download/appcast.xml`

The `DeeDock-TestFlight` scheme compiles the same app with `TESTFLIGHT` instead of `DIRECT_DISTRIBUTION`. It has no Sparkle package dependency, updater UI, or updater Info.plist keys. Choosing TestFlight at export time does not remove Sparkle from a direct archive. Always archive the correct scheme.

## Custom update window

DeeDock constructs `SPUUpdater` with its own `SPUUserDriver`. It does not instantiate `SPUStandardUpdaterController` or use Sparkle's standard windows. Sparkle still owns feed selection, downloads, verification, installation, and preference persistence. macOS owns any administrator authorization dialog required by installation.

The custom driver handles permission, checking, available and informational updates, release-note failures, incompatible updates, download and extraction progress, errors, restart decisions, delayed termination, and completion. Scheduled discoveries stay in the menu until the user opens them. Closing a check cancels it. Closing a download or extraction hides progress, which remains reachable from the menu. At the ready screen, closing the window has the documented Install on Quit behavior; Cancel stops that installation instead.

The permission window offers automatic checks or manual checks. System-profile sharing is disabled. Automatic downloads remain off by default. A user chooses Download Update or Install Update before any installation authorization can be requested.

`UpdateWindowView` and `UpdateWindowDetails` own the layout, colors, typography, progress, and controls. `UpdatePresentation` contains the display state and action labels. `UpdateUserDriver` owns Sparkle's reply blocks and consumes each reply once before calling the engine. Buttons carry a callback generation so a stale click cannot accept a later prompt. The termination retry callback is deliberately reusable, as Sparkle specifies.

Release notes use native text for plain text, Markdown, and HTML. HTML is parsed directly into native headings, paragraphs, lists, emphasis, and HTTPS links. Block spacing and hanging list indents are controlled by SwiftUI; HTML whitespace is collapsed before display. Remote styling, scripts, embedded media, and external entities are not loaded. Parsing is bounded to 512 KiB and runs off the main actor; dismissal or another offer cancels its result. An HTTPS release-note link remains available for the original document. Publishers should use text, headings, and lists for notes that read well in the app.

## Prepare the release

1. Increase `CURRENT_PROJECT_VERSION` in `Configuration/App.xcconfig` for every distributed build. Set `MARKETING_VERSION` there too. Both targets share these values and the bundle identifier. Sparkle compares build numbers, not Git tags.
2. Resolve packages in Xcode. The pinned Sparkle tools are under the resolved packages directory at `artifacts/sparkle/Sparkle/bin`.
3. Confirm the release machine has the DeeDock signing key. Run the following command with the actual tools path:

   ```sh
   SPARKLE_BIN='/absolute/path/to/SourcePackages/artifacts/sparkle/Sparkle/bin'
   "$SPARKLE_BIN/generate_keys" --account de.benjaminkraatz.DeeDock -p
   ```

   The public key must match `SPARKLE_PUBLIC_ED_KEY` in the direct target's build settings. The private key stays in the login Keychain under account `de.benjaminkraatz.DeeDock`. Do not generate a replacement key for each release.
4. Select `DeeDock`, choose Product → Archive, then distribute with Developer ID signing. Use Xcode's notarization and export flow. Preserve the hardened runtime and sign Sparkle's nested code through Xcode's export process. An unsigned local build is not distributable.

For command-line archives, run:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Release \
  -archivePath /absolute/path/to/DeeDock.xcarchive archive
xcodebuild -exportArchive -archivePath /absolute/path/to/DeeDock.xcarchive \
  -exportPath /absolute/path/to/export \
  -exportOptionsPlist /absolute/path/to/DeveloperID-ExportOptions.plist
```

Use an export-options plist saved from Xcode's Developer ID distribution flow for the current Xcode version and signing team. If the command-line export has not notarized the app, ZIP the exported app, submit it with `xcrun notarytool submit ... --keychain-profile <profile> --wait`, then staple the accepted ticket to the app with `xcrun stapler staple`. Recreate the final ZIP after stapling. Never modify the app after producing the signed update archive.

## Generate and publish the feed

Use a fresh staging directory containing only this release's exported app archive. The example tag is illustrative; use the version being released.

```sh
RELEASE_TAG='v0.1.2'
UPDATE_DIR='/absolute/path/to/update-staging'
EXPORTED_APP='/absolute/path/to/export/DeeDock.app'
mkdir -p "$UPDATE_DIR"
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
xcrun stapler validate "$EXPORTED_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "$EXPORTED_APP" "$UPDATE_DIR/DeeDock.zip"
"$SPARKLE_BIN/generate_appcast" \
  --account de.benjaminkraatz.DeeDock \
  --download-url-prefix "https://github.com/benjamin-kraatz/DeeDock/releases/download/$RELEASE_TAG/" \
  --maximum-deltas 0 "$UPDATE_DIR"
```

Inspect `appcast.xml`. Its enclosure must name the version-specific HTTPS download, include an EdDSA signature, and declare the intended build number, minimum macOS version, and supported architecture. The ZIP must contain only `DeeDock.app` at its root. This procedure signs the archive; it does not enable optional appcast signing.

Create a draft GitHub release with `DeeDock.zip` and `appcast.xml` as assets. Verify both assets before publishing the release as Latest. Every subsequent stable Latest release must carry `appcast.xml`; otherwise installed apps lose their feed. Do not mark a TestFlight-only or prerelease build as Latest. Keep older releases and their version-specific asset URLs intact.

A feed containing only the newest version is sufficient while supported OS and architecture requirements remain the same. If those requirements change, retain compatible older appcast entries and their original asset URLs so existing users still receive the last compatible build. Do not rewrite older enclosures to point at the newest release tag.

The existing v0.1.1 release predates Sparkle. Users must install the first Sparkle-enabled release manually. Until its feed asset is published, the configured feed will not deliver updates.

## Back up the signing key

Export only to secure storage outside the repository:

```sh
umask 077
"$SPARKLE_BIN/generate_keys" --account de.benjaminkraatz.DeeDock \
  -x /secure/location/DeeDock-sparkle-private-key
```

Keep an encrypted backup. On another release machine, use the same account with `-f /secure/location/DeeDock-sparkle-private-key`, then compare the public key using `-p`. Never put the private key in Git, release assets, issue comments, or logs. Consult Sparkle's key-rotation guidance before changing an established public key.

## Archive for TestFlight

Select `DeeDock-TestFlight` and archive that target. Its app still has the product name `DeeDock.app`, with ordinary build products isolated under `TestFlight`. Inspect the archive before upload: there must be no `Sparkle.framework`, Sparkle helpers, Sparkle load command, `SUFeedURL`, or `SUPublicEDKey`.

This target preserves the existing signing and sandbox settings. It establishes updater exclusion, not App Store Connect acceptance. Address any TestFlight entitlement or sandbox requirements separately rather than exporting the direct target as TestFlight.

## Verify an update before release

With explicit authorization, install an older Developer ID signed and notarized build, then update to a newer signed build through a staging feed. Verify relaunch, saved dock settings, manual checks, automatic-check consent and persistence, offline errors, invalid signatures, read-only installation locations, and reminders while another app has focus. Confirm German text, keyboard access, and menu availability during an active update.

Compilation and bundle inspection do not establish these runtime behaviors. No feed, release, or key backup is published automatically by this repository.

Sources: [Sparkle setup and distribution](https://sparkle-project.org/documentation/), [custom user drivers](https://sparkle-project.org/documentation/custom-user-interfaces/).

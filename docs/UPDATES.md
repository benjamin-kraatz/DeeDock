# Publish a DDock update

Use the `DeeDock` scheme for direct distribution. Its resources include the unchanged third-party notices from `ThirdParty/Sparkle-LICENSE.txt`. It includes Sparkle 2.9.6 and uses the public GitHub Releases feed:

`https://github.com/benjamin-kraatz/DeeDock/releases/latest/download/appcast.xml`

The `DeeDock-TestFlight` scheme compiles the same app with `TESTFLIGHT` instead of `DIRECT_DISTRIBUTION`. It has no Sparkle package dependency, updater UI, or updater Info.plist keys. Choosing TestFlight at export time does not remove Sparkle from a direct archive. Always archive the correct scheme.

## Who publishes

Esi is the release captain. Esi triggers and watches the [Release workflow](../.github/workflows/release.yml) nightly at 23:00 Europe/Berlin and on an explicit ship. Nara and other bots do not cut releases, hold Sparkle or signing secrets, or publish GitHub Latest.

The workflow is a placeholder. Signing, notarization, `generate_appcast`, and Latest publish are stubs until those steps are implemented. The repository already has the [six secrets](#secrets-checklist) the later `notarytool` and signing steps will consume. The manual archive path in this document stays valid.

GitHub Release body is English only. Sparkle release notes are bilingual German and English. See [Release notes](#release-notes).

## Custom update window

DDock constructs `SPUUpdater` with its own `SPUUserDriver`. It does not instantiate `SPUStandardUpdaterController` or use Sparkle's standard windows. Sparkle still owns feed selection, downloads, verification, installation, and preference persistence. macOS owns any administrator authorization dialog required by installation.

The custom driver handles permission, checking, available and informational updates, release-note failures, incompatible updates, download and extraction progress, errors, restart decisions, delayed termination, and completion. Scheduled discoveries stay in the menu until the user opens them. Closing a check cancels it. Closing a download or extraction hides progress, which remains reachable from the menu. At the ready screen, closing the window has the documented Install on Quit behavior; Cancel stops that installation instead.

The permission window offers automatic checks or manual checks. System-profile sharing is disabled. Automatic installation is on by default when automatic checks are enabled. Sparkle downloads scheduled updates in the background and installs them when DDock quits without a DDock confirmation. macOS may still require administrator authorization. General Settings shows the installed version and build number, and keeps separate controls for automatic checks and automatic installation.

`UpdateWindowView` and `UpdateWindowDetails` own the layout, colors, typography, progress, and controls. `UpdatePresentation` contains the display state and action labels. `UpdateUserDriver` owns Sparkle's reply blocks and consumes each reply once before calling the engine. Buttons carry a callback generation so a stale click cannot accept a later prompt. The termination retry callback is deliberately reusable, as Sparkle specifies.

Release notes use native text for plain text, Markdown, and HTML. HTML is parsed directly into native headings, paragraphs, lists, emphasis, and HTTPS links. Block spacing and hanging list indents are controlled by SwiftUI; HTML whitespace is collapsed before display. Remote styling, scripts, embedded media, and external entities are not loaded. Parsing is bounded to 512 KiB and runs off the main actor; dismissal or another offer cancels its result. An HTTPS release-note link remains available for the original document. Publishers should use text, headings, and lists for notes that read well in the app.

## Prepare the release

1. Increase `CURRENT_PROJECT_VERSION` in `Configuration/App.xcconfig` for every distributed build. Set `MARKETING_VERSION` there too. Both targets share these values and the bundle identifier. Sparkle compares build numbers, not Git tags.
2. Resolve packages in Xcode. The pinned Sparkle tools are under the resolved packages directory at `artifacts/sparkle/Sparkle/bin`.
3. Confirm the release machine has the DDock signing key. Run the following command with the actual tools path:

   ```sh
   SPARKLE_BIN='/absolute/path/to/SourcePackages/artifacts/sparkle/Sparkle/bin'
   "$SPARKLE_BIN/generate_keys" --account de.benjaminkraatz.DeeDock -p
   ```

   The public key must match `SPARKLE_PUBLIC_ED_KEY` in the direct target's build settings. The private key stays in the login Keychain under account `de.benjaminkraatz.DeeDock`. Do not generate a replacement key for each release.
4. Select `DeeDock`, choose Product → Archive, then distribute with Developer ID signing. Use Xcode's notarization and export flow. Preserve the hardened runtime and sign Sparkle's nested code through Xcode's export process. An unsigned local build is not distributable.

For command-line archives, run:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Release \
  -archivePath /absolute/path/to/DDock.xcarchive archive
xcodebuild -exportArchive -archivePath /absolute/path/to/DDock.xcarchive \
  -exportPath /absolute/path/to/export \
  -exportOptionsPlist /absolute/path/to/DeveloperID-ExportOptions.plist
```

Use an export-options plist saved from Xcode's Developer ID distribution flow for the current Xcode version and signing team. If the command-line export has not notarized the app, ZIP the exported app, submit it with `xcrun notarytool submit ... --keychain-profile <profile> --wait`, then staple the accepted ticket to the app with `xcrun stapler staple`. Recreate the final ZIP after stapling. Never modify the app after producing the signed update archive.

The Release workflow does not use a keychain profile. Later CI notarization uses `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` with `notarytool`. It does not use an App Store Connect API key. TestFlight stays on Xcode Cloud.

## Generate and publish the feed

Use a fresh staging directory containing only this release's exported app archive. The example tag is illustrative; use the version being released.

```sh
RELEASE_TAG='v0.1.2'
UPDATE_DIR='/absolute/path/to/update-staging'
EXPORTED_APP='/absolute/path/to/export/DDock.app'
mkdir -p "$UPDATE_DIR"
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
xcrun stapler validate "$EXPORTED_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "$EXPORTED_APP" "$UPDATE_DIR/DDock.zip"
"$SPARKLE_BIN/generate_appcast" \
  --account de.benjaminkraatz.DeeDock \
  --download-url-prefix "https://github.com/benjamin-kraatz/DeeDock/releases/download/$RELEASE_TAG/" \
  --maximum-deltas 0 "$UPDATE_DIR"
```

Inspect `appcast.xml`. Its enclosure must name the version-specific HTTPS download, include an EdDSA signature, and declare the intended build number, minimum macOS version, and supported architecture. The ZIP must contain only `DDock.app` at its root. This procedure signs the archive; it does not enable optional appcast signing.

Create a draft GitHub release with `DDock.zip` and `appcast.xml` as assets. Write the GitHub Release body in English only. Put bilingual Sparkle notes in `docs/releases/<MARKETING_VERSION>.md` and copy that file beside the ZIP as `DDock.md` before `generate_appcast`, so the appcast embeds German and English. Verify both assets before publishing the release as Latest. Every subsequent stable Latest release must carry `appcast.xml`; otherwise installed apps lose their feed. Do not mark a TestFlight-only or prerelease build as Latest. Keep older releases and their version-specific asset URLs intact.

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

Select `DeeDock-TestFlight` and archive that target. Its app still has the product name `DDock.app`, with ordinary build products isolated under `TestFlight`. Inspect the archive before upload: there must be no `Sparkle.framework`, Sparkle helpers, Sparkle load command, `SUFeedURL`, or `SUPublicEDKey`.

This target preserves the existing signing and sandbox settings. It establishes updater exclusion, not App Store Connect acceptance. Address any TestFlight entitlement or sandbox requirements separately rather than exporting the direct target as TestFlight. TestFlight uploads stay on Xcode Cloud. The Release workflow does not notarize or upload that scheme, and it does not use App Store Connect API keys.

## Verify an update before release

With explicit authorization, install an older Developer ID signed and notarized build, then update to a newer signed build through a staging feed. Verify relaunch, saved dock settings, manual checks, automatic-check consent and persistence, offline errors, invalid signatures, read-only installation locations, and reminders while another app has focus. Confirm German text, keyboard access, and menu availability during an active update.

Compilation and bundle inspection do not establish these runtime behaviors. Until the Release workflow stubs are replaced, no feed, release, or key backup is published automatically.

## Release notes

Keep two publications separate.

**GitHub Release body.** English only. Esi pastes or generates this when opening the draft. Do not put the German text in the GitHub body.

**Sparkle notes.** Bilingual German and English. The source file is `docs/releases/<MARKETING_VERSION>.md`, matching the existing `docs/releases/0.2.0.md` convention. New files use this shape:

```markdown
DDock 0.2.1, Build 18, benötigt macOS 27 und einen Mac mit Apple Silicon.

## Neue Funktionen

- German notes first, using the same heading style as 0.2.0.

## English

DDock 0.2.1, Build 18, requires macOS 27 and an Apple Silicon Mac.

### New features

- English notes that cover the same changes.
```

`generate_appcast` embeds a `.md` file whose base name matches the archive. Copy the version file to the staging folder as `DDock.md` next to `DDock.zip`. Sparkle 2.9.6 accepts Markdown. The in-app window parses headings, lists, and HTTPS links and does not load remote styling.

Existing `docs/releases/0.2.0.md` is German only. Add an `## English` section on the next version. Do not rewrite older published notes.

## Release pipeline

The [Release workflow](../.github/workflows/release.yml) is the intended CI path for the same archive, notarize, `generate_appcast`, draft, and Latest sequence described above.

Esi triggers it in two ways:

1. Nightly watch at 23:00 Europe/Berlin. The workflow uses cron `0 23 * * *` with `timezone: Europe/Berlin`. GitHub follows Central European Time in winter (23:00 Berlin is 22:00 UTC) and Central European Summer Time in summer (23:00 Berlin is 21:00 UTC). Do not read that cron as 23:00 UTC.
2. Explicit ship from **Actions → Release → Run workflow**, with intent `ship`.

Scheduled runs always use intent `watch`. They print version and secret-presence status. They do not publish. `ship` stays blocked until the stub steps are replaced.

Expected later runner: a Mac with Xcode 27 and a Developer ID identity. `macos-latest` in the workflow is a placeholder. A self-hosted pool can replace it without changing the step order.

On failure, Esi opens a high-priority Linear issue on project or label `release-pipeline`. Esi may add label `Bot-Nara` once if Nara should fix pipeline code. Nara does not cut the release, hold secrets, or publish Latest.

## Secrets checklist

The Release workflow consumes these six repository secrets. Names only. Do not put values in the repository, the workflow file, issue comments, or logs.

Apple ID notarization for `notarytool` (`--apple-id`, `--password`, `--team-id`):

- [ ] `APPLE_ID`
- [ ] `APPLE_APP_SPECIFIC_PASSWORD`
- [ ] `APPLE_TEAM_ID`

Developer ID signing:

- [ ] `DEVELOPER_ID_APPLICATION_CERTIFICATE`
- [ ] `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`

Sparkle EdDSA private key. The matching public key is `SPARKLE_PUBLIC_ED_KEY` in the direct target. Today's login Keychain account is `de.benjaminkraatz.DeeDock`. Never commit the private key or generate a replacement for each release:

- [ ] `SPARKLE_PRIVATE_ED_KEY`

Do not add App Store Connect API key secrets. TestFlight stays on Xcode Cloud.

`GITHUB_TOKEN` with `contents: write` is the default for a later draft release, asset upload, and Latest publish. There is no separate GitHub token secret.

Sources: [Sparkle setup and distribution](https://sparkle-project.org/documentation/), [custom user drivers](https://sparkle-project.org/documentation/custom-user-interfaces/).

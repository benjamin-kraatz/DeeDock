# Publish a DDock update

Use the `DeeDock` scheme for direct distribution. Its resources include the unchanged third-party notices from `ThirdParty/Sparkle-LICENSE.txt`. It includes Sparkle 2.9.6 and uses the public GitHub Releases feed:

`https://github.com/benjamin-kraatz/DeeDock/releases/latest/download/appcast.xml`

The `DeeDock-TestFlight` scheme compiles the same app with `TESTFLIGHT` instead of `DIRECT_DISTRIBUTION`. It has no Sparkle package dependency, updater UI, or updater Info.plist keys. Choosing TestFlight at export time does not remove Sparkle from a direct archive. Always archive the correct scheme.

## Who publishes

Esi is the release captain. Esi alone dispatches the [Release workflow](../.github/workflows/release.yml) from **Actions → Release → Run workflow**. The workflow has no `schedule`, push, or pull_request trigger. If Esi wants a nightly watch, that is her routine, not a GitHub cron.

Nara and other bots do not dispatch Release, bump `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` on feature work, hold Sparkle or signing secrets, or publish GitHub Latest. Version bumps and bilingual notes belong in a separate release-prep PR. Esi merges that PR before she dispatches.

`intent=watch` is an optional dry-run on `ubuntu-latest`. It prints the version, secret presence, and notes check. It does not start `xcode-27`.

`intent=ship` preflights on Linux, then archives on `xcode-27`, then opens a draft GitHub Release back on `ubuntu-latest`. It does not publish Latest unless Esi sets `publish_latest`. The first smoke path stays draft-only. The [manual archive path](#prepare-the-release) stays valid.

GitHub Release body is English only. Sparkle release notes are bilingual German and English. See [Release notes](#release-notes).

## Custom update window

DDock constructs `SPUUpdater` with its own `SPUUserDriver`. It does not instantiate `SPUStandardUpdaterController` or use Sparkle's standard windows. Sparkle still owns feed selection, downloads, verification, installation, and preference persistence. macOS owns any administrator authorization dialog required by installation.

The custom driver handles permission, checking, available and informational updates, release-note failures, incompatible updates, download and extraction progress, errors, restart decisions, delayed termination, and completion. Scheduled discoveries stay in the menu until the user opens them. Closing a check cancels it. Closing a download or extraction hides progress, which remains reachable from the menu. At the ready screen, closing the window has the documented Install on Quit behavior; Cancel stops that installation instead.

The permission window offers automatic checks or manual checks. System-profile sharing is disabled. Automatic installation is on by default when automatic checks are enabled. Sparkle downloads scheduled updates in the background and installs them when DDock quits without a DDock confirmation. macOS may still require administrator authorization. General Settings shows the installed version and build number, and keeps separate controls for automatic checks and automatic installation.

`UpdateWindowView` and `UpdateWindowDetails` own the layout, colors, typography, progress, and controls. `UpdatePresentation` contains the display state and action labels. `UpdateUserDriver` owns Sparkle's reply blocks and consumes each reply once before calling the engine. Buttons carry a callback generation so a stale click cannot accept a later prompt. The termination retry callback is deliberately reusable, as Sparkle specifies.

Release notes use native text for plain text, Markdown, and HTML. HTML is parsed directly into native headings, paragraphs, lists, emphasis, and HTTPS links. Block spacing and hanging list indents are controlled by SwiftUI; HTML whitespace is collapsed before display. Remote styling, scripts, embedded media, and external entities are not loaded. Parsing is bounded to 512 KiB and runs off the main actor; dismissal or another offer cancels its result. An HTTPS release-note link remains available for the original document. Publishers should use text, headings, and lists for notes that read well in the app.

When a later release also publishes `DDock-comic.md` next to `DDock.md`, the Update window renders that comic first and keeps the full notes below. Panel PNGs load only over HTTPS from GitHub Releases or `raw.githubusercontent.com` for `benjamin-kraatz/DeeDock`, or from local files in previews and tests. A miss hides the art and keeps the copy. The app does not load Google Fonts, remote stylesheets, scripts, or other embedded media. Static `*-comic.html` review files may link Google Fonts. That link never enters the Update window. See [What’s New comics](releases/COMIC-README.md).

The 0.4.1 cut is this renderer only. It does not add `0.4.1-comic.md` or `assets/0.4.1/`. The first authored comic stays on 0.5.0.

## Prepare the release

1. Increase `CURRENT_PROJECT_VERSION` in `Configuration/App.xcconfig` for every distributed build. Set `MARKETING_VERSION` there too. Both targets share these values and the bundle identifier. Sparkle compares build numbers, not Git tags. Versions live only in that xcconfig.
2. Grep `DeeDock.xcodeproj/project.pbxproj` for `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION`. Delete any copies from target build settings so Xcode inherits from `App.xcconfig`. If a target cannot inherit, copy the same values from the xcconfig into that target. If you open the target in Xcode, confirm Version and Build still come from `App.xcconfig`. The General tab can write those keys back into the pbxproj.
3. Resolve packages in Xcode. The pinned Sparkle tools are under the resolved packages directory at `artifacts/sparkle/Sparkle/bin`.
4. Confirm the release machine has the DDock signing key. Run the following command with the actual tools path:

   ```sh
   SPARKLE_BIN='/absolute/path/to/SourcePackages/artifacts/sparkle/Sparkle/bin'
   "$SPARKLE_BIN/generate_keys" --account de.benjaminkraatz.DeeDock -p
   ```

   The public key must match `SPARKLE_PUBLIC_ED_KEY` in the direct target's build settings. The private key stays in the login Keychain under account `de.benjaminkraatz.DeeDock`. Do not generate a replacement key for each release.
5. Select `DeeDock`, choose Product → Archive, then distribute with Developer ID signing. Use Xcode's notarization and export flow. Preserve the hardened runtime and sign Sparkle's nested code through Xcode's export process. An unsigned local build is not distributable.

For command-line archives, run:

```sh
xcodebuild -project DeeDock.xcodeproj -scheme DeeDock -configuration Release \
  -archivePath /absolute/path/to/DDock.xcarchive archive
xcodebuild -exportArchive -archivePath /absolute/path/to/DDock.xcarchive \
  -exportPath /absolute/path/to/export \
  -exportOptionsPlist /absolute/path/to/DeveloperID-ExportOptions.plist
```

Use an export-options plist saved from Xcode's Developer ID distribution flow for the current Xcode version and signing team. If the command-line export has not notarized the app, ZIP the exported app, submit it with `xcrun notarytool submit ... --keychain-profile <profile> --wait`, then staple the accepted ticket to the app with `xcrun stapler staple`. Recreate the final ZIP after stapling. Never modify the app after producing the signed update archive.

The Release workflow does not use a keychain profile. CI notarization runs:

```sh
xcrun notarytool submit <zip> --apple-id --password --team-id --wait
```

It reads `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`. It does not use an App Store Connect API key. TestFlight stays on Xcode Cloud.

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

Create a draft GitHub release with `DDock.zip` and `appcast.xml` as assets. When `docs/releases/<MARKETING_VERSION>.md` exists, copy it beside the ZIP as `DDock.md` before `generate_appcast`, and upload that `DDock.md` with the draft. When `docs/releases/<MARKETING_VERSION>-comic.md` is on the shipped commit, the Release workflow also stages it as `DDock-comic.md`, copies each `docs/releases/assets/<MARKETING_VERSION>/panel-0N.png` as a flat `panel-0N.png`, and uploads those files on the same draft. The staged comic rewrites `assets/<ver>/panel-0N.png` links to `panel-0N.png` so the Update window can load art next to `DDock-comic.md`. A missing comic file is skipped and the notes-only ship still succeeds. Write the GitHub Release body in English only. Sparkle notes stay bilingual German and English. 0.4.1 has no comic package.

The Release workflow stops at that draft. Leave `publish_latest` off until Benn confirms a Latest cut. Verify both assets before anyone marks the release as Latest. Every subsequent stable Latest release must carry `appcast.xml`; otherwise installed apps lose their feed. Do not mark a TestFlight-only or prerelease build as Latest. Keep older releases and their version-specific asset URLs intact.

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

Compilation and bundle inspection do not establish these runtime behaviors. `intent=watch` never publishes. `intent=ship` opens a draft only. Latest stays off until Esi sets `publish_latest`. The workflow never writes a key backup.

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

A What’s New comic is optional and is not part of 0.4.1. Author it as `docs/releases/<MARKETING_VERSION>-comic.md` using [COMIC-TEMPLATE.md](releases/COMIC-TEMPLATE.md) on a later release-prep PR. Keep the 0.5.0 Focus, Compost, and Gossip comic on that version. Do not attach it to a 0.4.x draft. When that file is present, the Release workflow uploads `DDock-comic.md` and the matching `panel-0N.png` files onto the GitHub Release next to `DDock.md`. See [What’s New comics](releases/COMIC-README.md) for the asset names.

Existing `docs/releases/0.2.0.md` is German only. Add an `## English` section on the next version. Do not rewrite older published notes.

## Release pipeline

The [Release workflow](../.github/workflows/release.yml) is `workflow_dispatch` only. It splits cheap checks from the Mac archive.

Esi dispatches it. She chooses `intent=watch` for a dry-run, or `intent=ship` after the release-prep PR is on `main`. Leave **publish_latest** unchecked.

Release-prep is a separate PR. It raises `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` only in `Configuration/App.xcconfig` and adds bilingual notes at `docs/releases/<MARKETING_VERSION>.md`. Confirm `DeeDock.xcodeproj/project.pbxproj` target build settings inherit those keys instead of repeating them. Esi merges that PR before she dispatches. Feature work does not bump those versions.

**watch** (`ubuntu-latest`). Every dispatch runs this job. `intent=watch` stops here. It reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `Configuration/App.xcconfig`, reports the six secrets by name, checks `docs/releases/<MARKETING_VERSION>.md` for an `## English` section, and reports whether `docs/releases/<MARKETING_VERSION>-comic.md` and any `panel-0N.png` files exist. A missing comic does not fail watch or ship. It does not archive, import a certificate, or start `xcode-27`.

**archive** (`xcode-27`). `intent=ship` only, after watch succeeds. Watch fails first if a secret or the bilingual notes file is missing, so the Mac job does not start. Then, in order:

1. Confirm the image has Xcode 27 and the macOS 27 SDK.
2. Resolve Sparkle tools from the pinned 2.9.6 package (`generate_appcast` under the cloned `artifacts/sparkle` tree).
3. Import `DEVELOPER_ID_APPLICATION_CERTIFICATE` into a temporary keychain. The job deletes that keychain when it finishes.
4. Archive the `DeeDock` scheme for Release with Developer ID and hardened runtime. This is not TestFlight.
5. Export with a generated Developer ID options plist, then `xcrun notarytool submit ... --apple-id --password --team-id --wait`, then `stapler staple`. Nested Sparkle code stays signed. The job does not weaken hardened runtime.
6. Verify `codesign --deep --strict` and `stapler validate`.
7. Build `DDock.zip` with `ditto`, copy bilingual notes to `DDock.md`, copy a What’s New comic to `DDock-comic.md` plus flat `panel-0N.png` files when that comic exists, and run `generate_appcast --ed-key-file - --maximum-deltas 0`.
8. Upload `DDock.zip`, `appcast.xml`, `DDock.md`, version metadata, and any staged comic files as a workflow artifact.

Do not run those archive steps in parallel.

**draft** (`ubuntu-latest`). After archive. Downloads the artifacts and opens a draft GitHub Release for `v<MARKETING_VERSION>` with an English-only body. Upload `DDock.zip`, `appcast.xml`, and `DDock.md`. When `DDock-comic.md` and `panel-0N.png` are in the artifact, upload those too. The job refuses to overwrite a published or Latest release. `xcode-27` does not call `gh`.

`publish_latest` defaults to false. Turn it on only after Benn confirms a Latest cut. The first smoke path must stay a draft.

`xcode-27` is Benn's Mac image. DDock still needs Xcode 27 and the macOS 27 SDK. If the image reports an older toolchain, archive fails and tells Esi and Benn. Developer ID import uses a temporary keychain on that runner.

On failure, Esi opens a high-priority Linear issue on project or label `release-pipeline` and SendToAgent-pings Nara with the failure blob. Do not add label `Bot-Nara` on that issue. `Bot-Nara` stays on feature tickets only. Nara does not dispatch Release, bump versions on feature work, hold secrets, or publish Latest.

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

These are the assumed secret formats. Confirm them against what is stored. Never paste those values into the repo, a PR, or logs.

- `DEVELOPER_ID_APPLICATION_CERTIFICATE` is the base64 encoding of a PKCS#12 (`.p12`) that holds the Developer ID Application identity.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` is that `.p12` password.
- `SPARKLE_PRIVATE_ED_KEY` is the first line written by `generate_keys --account de.benjaminkraatz.DeeDock -x`. That line is Sparkle's base64 EdDSA secret. The workflow feeds it to `generate_appcast --ed-key-file -`. It does not use deprecated `-s`.

Do not add App Store Connect API key secrets. TestFlight stays on Xcode Cloud.

`GITHUB_TOKEN` with `contents: write` opens the draft, uploads assets, and can publish Latest only when `publish_latest` is true. There is no separate GitHub token secret.

Sources: [Sparkle setup and distribution](https://sparkle-project.org/documentation/), [custom user drivers](https://sparkle-project.org/documentation/custom-user-interfaces/).

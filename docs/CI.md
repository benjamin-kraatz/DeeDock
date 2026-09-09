# Run DDock's GitHub Actions

DDock compiles on GitHub-hosted runners. Publishing a signed update still happens on a release machine. See [Publish a DDock update](UPDATES.md).

## Compile a pull request

1. Open a pull request against `main`.
2. Wait for the CI workflow. It parses the string catalog and `Package.resolved`, then compiles three unsigned builds on `xcode-27`.
3. Fix the job that failed. A green compile does not mean tests ran.

The three compiles are Debug `DeeDock`, Release `DeeDock`, and Release `DeeDock-TestFlight`.

Pushes to `main` run the same workflow. A newer run on the same branch cancels an older one that is still in progress.

## Compile the same way locally

From the repository root, on a Mac with Xcode 27:

```sh
scripts/ci-validate-catalogs.sh
scripts/ci-build.sh DeeDock Debug
scripts/ci-build.sh DeeDock Release
scripts/ci-build.sh DeeDock-TestFlight Release
```

`CODE_SIGNING_ALLOWED=NO` keeps the compile free of a local signing identity.

## Run the release compile

1. Open the Actions tab.
2. Choose **Release compile**.
3. Run the workflow on the branch you intend to ship.
4. When it succeeds, follow [Publish a DDock update](UPDATES.md) on the machine that holds the Developer ID certificate and the Sparkle key.

Do not upload the unsigned products from the workflow.

## Runner image

Use `xcode-27`. GitHub now keys hosted macOS images to a major Xcode version. `macos-latest` is macOS 26 with Xcode 26, which cannot compile a macOS 27 deployment target.

`xcode-27-xlarge` is the same toolchain on a larger runner. Larger runners are billed even for public repositories. Use the standard `xcode-27` label until a compile proves it needs more cores.

The image is arm64 only. That matches DDock.

The image is still in public preview. Installed tool versions can move. `scripts/ci-select-xcode.sh` points `xcode-select` at Xcode.app and replaces a leftover Command Line Tools `SDKROOT` before any compile. `scripts/ci-install-metal-toolchain.sh` downloads Apple's Metal component when the image omitted it. DDock compiles `RunningIndicatorShaders.metal`. The job then prints `sw_vers`, `xcode-select -p`, and `xcodebuild -showsdks`.

Standard hosted-runner minutes on this public repository are free. Fork pull requests still need the usual first-time workflow approval.

## What Actions do not do

- The Xcode `DeeDockTests` target is not executed. Several production sources are still missing from that target.
- Workflows do not sign, notarize, staple, generate `appcast.xml`, or publish a GitHub Release.
- The Sparkle private key stays out of GitHub secrets.

Repair `DeeDockTests` membership before adding `xcodebuild test` to CI. Notarization from Actions would need a GitHub Environment, required reviewers, and certificates stored as secrets.

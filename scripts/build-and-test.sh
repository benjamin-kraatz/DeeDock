#!/bin/sh
# Debug build of the DeeDock scheme and the hosted DeeDockTests target.
#
# Unsigned: CODE_SIGNING_ALLOWED=NO. No Developer ID, no notarization, no
# Sparkle private key. POSTHOG_PROJECT_TOKEN and POSTHOG_HOST are passed
# empty so a machine environment cannot turn analytics on for this run.
#
# CI calls this from .github/workflows/ci.yml. The optional pre-push hook
# calls it too. Set DERIVED_DATA_PATH and RESULT_BUNDLE_PATH to override
# the local defaults under $TMPDIR.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

work="${TMPDIR:-/tmp}/ddock-build-and-test"
derived="${DERIVED_DATA_PATH:-$work/DerivedData}"
results="${RESULT_BUNDLE_PATH:-$work/DeeDock.xcresult}"

mkdir -p "$(dirname "$derived")" "$(dirname "$results")"
# xcodebuild refuses to overwrite an existing result bundle.
rm -rf "$results"

xcodebuild \
  -project "$root/DeeDock.xcodeproj" \
  -scheme DeeDock \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived" \
  -resultBundlePath "$results" \
  -only-testing:DeeDockTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  POSTHOG_PROJECT_TOKEN= \
  POSTHOG_HOST= \
  test

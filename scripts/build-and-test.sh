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
#
# CI-only environment:
#   CLONED_SOURCE_PACKAGES_PATH  stable directory for SPM checkouts
#   SPM_SOURCES_CACHE_HIT        "true" when that directory was restored
#   ENABLE_CODE_COVERAGE         YES or NO; unset keeps the scheme setting
#
# Compile jobs follow hw.ncpu. Test runners stay at the scheme default:
# DeeDockTests already finishes in a few seconds.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

work="${TMPDIR:-/tmp}/ddock-build-and-test"
derived="${DERIVED_DATA_PATH:-$work/DerivedData}"
results="${RESULT_BUNDLE_PATH:-$work/DeeDock.xcresult}"

ncpu=$(sysctl -n hw.ncpu)
physical=$(sysctl -n hw.physicalcpu)
logical=$(sysctl -n hw.logicalcpu)
echo "runner cores: hw.ncpu=$ncpu hw.physicalcpu=$physical hw.logicalcpu=$logical"
echo "xcodebuild -jobs $ncpu"

mkdir -p "$(dirname "$derived")" "$(dirname "$results")"
# xcodebuild refuses to overwrite an existing result bundle.
rm -rf "$results"

set -- \
  -project "$root/DeeDock.xcodeproj" \
  -scheme DeeDock \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived" \
  -resultBundlePath "$results" \
  -only-testing:DeeDockTests \
  -jobs "$ncpu" \
  -IDEBuildOperationMaxNumberOfConcurrentCompileTasks="$ncpu" \
  -showBuildTimingSummary

if [ -n "${CLONED_SOURCE_PACKAGES_PATH:-}" ]; then
  mkdir -p "$CLONED_SOURCE_PACKAGES_PATH"
  set -- "$@" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH" \
    -onlyUsePackageVersionsFromResolvedFile
  # A restored checkout already matches Package.resolved. Resolving again
  # would rewrite it and defeat the cache.
  if [ "${SPM_SOURCES_CACHE_HIT:-}" = "true" ]; then
    set -- "$@" -disableAutomaticPackageResolution
  fi
fi

if [ -n "${ENABLE_CODE_COVERAGE:-}" ]; then
  set -- "$@" -enableCodeCoverage "$ENABLE_CODE_COVERAGE"
fi

xcodebuild "$@" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  POSTHOG_PROJECT_TOKEN= \
  POSTHOG_HOST= \
  test

if [ -n "${CLONED_SOURCE_PACKAGES_PATH:-}" ]; then
  echo "SPM source packages size: $(du -sh "$CLONED_SOURCE_PACKAGES_PATH" | awk '{print $1}')"
fi

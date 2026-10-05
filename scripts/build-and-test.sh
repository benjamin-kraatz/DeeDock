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
#   STRIP_APP_PRODUCTS           "1" deletes DOKK and DeeDockTests outputs
#                                before xcodebuild. CI restores package
#                                intermediates into DERIVED_DATA_PATH and
#                                then sets this so the app is compiled again.
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
echo "workspace: $root"
echo "DerivedData path: $derived"

# Delete DOKK and DeeDockTests outputs, including explicit modules named
# for the app. Package intermediates stay. Missing app outputs make
# xcodebuild compile and link those targets again.
strip_app_products() {
  rm -rf \
    "$derived/Build/Intermediates.noindex/DeeDock.build" \
    "$derived/Build/Products/Debug/DOKK.app" \
    "$derived/Build/Products/Debug/DOKK.app.dSYM" \
    "$derived/Build/Products/Debug/DeeDockTests.xctest" \
    "$derived/Build/Products/Debug/DeeDockTests.xctest.dSYM" \
    "$derived/Build/Products/Debug/DeeDock.swiftmodule" \
    "$derived/Build/Products/Debug/DeeDock.swiftdoc" \
    "$derived/Build/Products/Debug/DeeDock.swiftsourceinfo" \
    "$derived/Build/Products/Debug/DeeDock.abi.json" \
    "$derived/Build/Products/Debug/DeeDockTests.swiftmodule" \
    "$derived/Build/Products/Debug/DeeDockTests.swiftdoc" \
    "$derived/Build/Products/Debug/DeeDockTests.swiftsourceinfo" \
    "$derived/Build/Products/Debug/DeeDockTests.abi.json" \
    "$derived/Index.noindex"

  for tree in \
    "$derived/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules" \
    "$derived/Build/Intermediates.noindex/ExplicitPrecompiledModules" \
    "$derived/Build/Intermediates.noindex/PrecompiledHeaders" \
    "$derived/ModuleCache.noindex" \
    "$derived/SDKExplicitPrecompiledModules"
  do
    [ -d "$tree" ] || continue
    find "$tree" \( -name '*DeeDock*' -o -name 'DOKK.app' -o -name 'DOKK.app.dSYM' \) -prune -exec rm -rf {} +
  done

  if [ -e "$derived/Build/Products/Debug/DOKK.app" ] || [ -d "$derived/Build/Intermediates.noindex/DeeDock.build" ]; then
    echo "DeeDock products are still present after strip." >&2
    exit 1
  fi
}

mkdir -p "$(dirname "$derived")" "$(dirname "$results")"
# xcodebuild refuses to overwrite an existing result bundle.
rm -rf "$results"

if [ "${STRIP_APP_PRODUCTS:-}" = "1" ]; then
  echo "Removing cached DOKK and DeeDockTests products"
  strip_app_products
fi

if [ -d "$derived/Build/Intermediates.noindex/PostHog.build" ]; then
  echo "SPM package intermediates: present"
else
  echo "SPM package intermediates: absent"
fi

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

# The index store is large, and a missing Index.noindex makes every
# compile task look out of date. CI does not index.
if [ "${STRIP_APP_PRODUCTS:-}" = "1" ]; then
  set -- "$@" COMPILER_INDEX_STORE_ENABLE=NO
fi

xcodebuild "$@" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  POSTHOG_PROJECT_TOKEN= \
  POSTHOG_HOST= \
  test

if [ -d "$derived/Build/Intermediates.noindex/DeeDock.build" ]; then
  echo "DeeDock intermediates: present"
else
  echo "DeeDock intermediates: absent" >&2
  exit 1
fi

if [ -n "${CLONED_SOURCE_PACKAGES_PATH:-}" ]; then
  echo "SPM source packages size: $(du -sh "$CLONED_SOURCE_PACKAGES_PATH" | awk '{print $1}')"
fi

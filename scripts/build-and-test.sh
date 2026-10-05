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
#   SPM_PRODUCTS_CACHE_PATH      compiled products of SPM dependencies only
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

# App and test products must never enter the SPM product cache.
is_app_owned_product() {
  case "$1" in
    DOKK.app|DOKK.app.dSYM|DeeDockTests.xctest|DeeDockTests.xctest.dSYM|DeeDock.swiftmodule|DeeDock.swiftdoc|DeeDock.swiftsourceinfo|DeeDock.abi.json|DeeDockTests.swiftmodule|DeeDockTests.swiftdoc|DeeDockTests.swiftsourceinfo|DeeDockTests.abi.json|*.dSYM)
      return 0
      ;;
  esac
  return 1
}

# Drop DOKK and DeeDockTests outputs after a package-product restore.
# DerivedData for those targets stays uncached; deleting the leftovers
# forces this job to compile and link them again.
strip_app_products() {
  rm -rf \
    "$derived/Build/Intermediates.noindex/DeeDock.build" \
    "$derived/Build/Intermediates.noindex/XCBuildData/PIFCache" \
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
    "$derived/Build/Products/Debug/DeeDockTests.abi.json"
}

# Copy cached package intermediates and products into this job's DerivedData.
# The build database keeps absolute paths, so CI restores it at the same
# DerivedData path. PIFCache is removed so the project model is read again.
seed_spm_products() {
  cache="${SPM_PRODUCTS_CACHE_PATH:-}"
  [ -n "$cache" ] || return 0
  if [ -d "$cache/Build" ]; then
    echo "Seeding SPM build products from $cache"
    rm -rf "$derived/Build"
    mkdir -p "$derived"
    cp -R "$cache/Build" "$derived/"
  else
    echo "SPM build products cache is empty"
  fi
  strip_app_products
}

# Keep package *.build directories, package products, and XCBuildData.
# DeeDock.build is the app project (app target and DeeDockTests).
export_spm_products() {
  cache="${SPM_PRODUCTS_CACHE_PATH:-}"
  [ -n "$cache" ] || return 0
  rm -rf "$cache"
  mkdir -p "$cache/Build/Intermediates.noindex" "$cache/Build/Products/Debug"

  intermediates="$derived/Build/Intermediates.noindex"
  if [ -d "$intermediates" ]; then
    for dir in "$intermediates"/*.build; do
      [ -d "$dir" ] || continue
      base=$(basename "$dir")
      case "$base" in
        DeeDock.build) continue ;;
      esac
      cp -R "$dir" "$cache/Build/Intermediates.noindex/"
    done
    if [ -d "$intermediates/GeneratedModuleMaps" ]; then
      cp -R "$intermediates/GeneratedModuleMaps" "$cache/Build/Intermediates.noindex/"
    fi
    if [ -d "$intermediates/XCBuildData" ]; then
      cp -R "$intermediates/XCBuildData" "$cache/Build/Intermediates.noindex/"
      rm -rf "$cache/Build/Intermediates.noindex/XCBuildData/PIFCache"
    fi
  fi

  products="$derived/Build/Products/Debug"
  if [ -d "$products" ]; then
    for item in "$products"/*; do
      [ -e "$item" ] || continue
      base=$(basename "$item")
      if is_app_owned_product "$base"; then
        continue
      fi
      cp -R "$item" "$cache/Build/Products/Debug/"
    done
  fi

  if [ -e "$cache/Build/Products/Debug/DOKK.app" ] || [ -d "$cache/Build/Intermediates.noindex/DeeDock.build" ]; then
    echo "Refusing to cache DeeDock app or test products." >&2
    exit 1
  fi
  echo "SPM products cache size: $(du -sh "$cache" | awk '{print $1}')"
}

mkdir -p "$(dirname "$derived")" "$(dirname "$results")"
# xcodebuild refuses to overwrite an existing result bundle.
rm -rf "$results"

seed_spm_products

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

export_spm_products

if [ -n "${CLONED_SOURCE_PACKAGES_PATH:-}" ]; then
  echo "SPM source packages size: $(du -sh "$CLONED_SOURCE_PACKAGES_PATH" | awk '{print $1}')"
fi

#!/bin/sh
# Compile one Xcode scheme without a signing identity.
# Matches the unsigned xcodebuild flags used in docs/ACCEPTANCE.md.
set -eu

scheme=${1:?usage: ci-build.sh <scheme> <configuration> [derivedDataPath]}
configuration=${2:?usage: ci-build.sh <scheme> <configuration> [derivedDataPath]}
derived=${3:-/tmp/DeeDock-ci}

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# A missing Command Line Tools SDKROOT makes xcodebuild look in the wrong place.
if [ -n "${SDKROOT:-}" ] && [ ! -e "$SDKROOT" ]; then
	unset SDKROOT
fi

xcodebuild \
	-project "$root/DeeDock.xcodeproj" \
	-scheme "$scheme" \
	-configuration "$configuration" \
	-destination 'platform=macOS' \
	-derivedDataPath "$derived" \
	CODE_SIGNING_ALLOWED=NO \
	build

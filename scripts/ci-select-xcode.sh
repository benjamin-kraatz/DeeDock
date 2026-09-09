#!/bin/sh
# Point later steps at full Xcode, not a leftover Command Line Tools SDKROOT.
# The xcode-27 image has advertised that leftover, which makes xcrun look for
# /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk.
set -eu

xcode_dev=""
for candidate in \
	/Applications/Xcode.app/Contents/Developer \
	/Applications/Xcode_27.app/Contents/Developer \
	/Applications/Xcode_27.0.app/Contents/Developer \
	/Applications/Xcode_27.0.0.app/Contents/Developer
do
	if [ -d "$candidate" ]; then
		xcode_dev=$candidate
		break
	fi
done

if [ -z "$xcode_dev" ]; then
	echo 'error: Xcode.app is not installed.' >&2
	ls /Applications >&2 || true
	exit 1
fi

# Resolve aliases so xcode-select does not follow a stale Xcode.app symlink.
xcode_dev=$(CDPATH= cd -- "$xcode_dev" && pwd -P)

if [ "$(id -u)" -eq 0 ]; then
	xcode-select -s "$xcode_dev"
else
	sudo xcode-select -s "$xcode_dev"
fi

unset SDKROOT
DEVELOPER_DIR=$xcode_dev
SDKROOT=$(DEVELOPER_DIR="$DEVELOPER_DIR" xcrun --sdk macosx --show-sdk-path)
export DEVELOPER_DIR SDKROOT

if [ -n "${GITHUB_ENV:-}" ]; then
	printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >>"$GITHUB_ENV"
	printf 'SDKROOT=%s\n' "$SDKROOT" >>"$GITHUB_ENV"
fi

echo "DEVELOPER_DIR=$DEVELOPER_DIR"
echo "SDKROOT=$SDKROOT"
xcode-select -p
xcodebuild -version

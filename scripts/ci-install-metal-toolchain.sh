#!/bin/sh
# Xcode 27 ships the metal compiler as a separate component.
# -showComponent exits 0 even when Status is uninstalled.
set -eu

metal_status() {
	xcodebuild -showComponent metalToolchain 2>/dev/null |
		awk -F': ' '/^Status:/ { print tolower($2); exit }'
}

echo 'Metal toolchain before install:'
xcodebuild -showComponent metalToolchain || true
status=$(metal_status || true)
echo "parsed status: ${status:-unknown}"

if [ "$status" = installed ]; then
	exit 0
fi

echo 'Downloading Metal toolchain...'
xcodebuild -downloadComponent MetalToolchain

echo 'Metal toolchain after download:'
xcodebuild -showComponent metalToolchain || true
status=$(metal_status || true)
echo "parsed status: ${status:-unknown}"

if [ "$status" = installed ]; then
	exit 0
fi

echo 'error: Metal toolchain is still not installed after download.' >&2
exit 1

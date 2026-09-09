#!/bin/sh
# Xcode 27 ships the metal compiler as a separate component.
# The xcode-27 runner image does not preinstall it.
set -eu

if xcodebuild -showComponent metalToolchain >/dev/null 2>&1; then
	echo 'Metal toolchain is already installed.'
	xcodebuild -showComponent metalToolchain
	exit 0
fi

echo 'Downloading Metal toolchain...'
xcodebuild -downloadComponent MetalToolchain
xcodebuild -showComponent metalToolchain

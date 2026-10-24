#!/bin/zsh
set -e
cd "$(dirname "$0")"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos27.0 *.swift -o CompanionLabBin
echo "built $(pwd)/CompanionLabBin"

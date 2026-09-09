#!/bin/sh
# Confirm committed JSON catalogs still parse.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

python3 -m json.tool "$root/DeeDock/Resources/Localizable.xcstrings" >/dev/null
python3 -m json.tool "$root/DeeDock.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" >/dev/null

echo 'Catalog JSON parsed.'

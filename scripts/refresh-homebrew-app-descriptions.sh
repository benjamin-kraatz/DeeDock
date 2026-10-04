#!/bin/sh
# Regenerates the bundled Homebrew cask descriptions that Robi uses to understand installed apps.
# Run it by hand every few months and commit the result; the app never contacts Homebrew itself, so
# shipping the whole catalog reveals nothing about which apps a user has installed.
#
# Source: https://formulae.brew.sh/api/cask.json (Homebrew cask metadata, BSD-2-Clause).
# Output: DeeDock/Resources/AppDescriptions/HomebrewAppDescriptions.json
#   bundleIdentifiers: bundle identifier (from the cask's uninstall/zap `quit` stanzas) -> description
#   appNames:          lowercased .app name without extension (from the `app` artifact) -> description
# When several casks install the same app (firefox, firefox@beta), the shortest token wins.
# Also refreshes DeeDock/Resources/AppDescriptions/HomebrewCaskLicense.txt, which Settings › About shows
# because the license requires binary distributions to reproduce it.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
destination="$root/DeeDock/Resources/AppDescriptions/HomebrewAppDescriptions.json"
download=$(mktemp)
trap 'rm -f "$download"' EXIT
curl --fail --silent --show-error --location https://formulae.brew.sh/api/cask.json -o "$download"
mkdir -p "$(dirname "$destination")"
curl --fail --silent --show-error --location https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/LICENSE \
    -o "$(dirname "$destination")/HomebrewCaskLicense.txt"
python3 - "$download" "$destination" <<'PYTHON'
import datetime, json, os, sys

casks = json.load(open(sys.argv[1]))
bundles, names = {}, {}

def strings(value):
    if isinstance(value, str): return [value]
    if isinstance(value, list): return [item for entry in value for item in strings(entry)]
    return []

for cask in sorted(casks, key=lambda cask: (len(cask["token"]), cask["token"])):
    description = (cask.get("desc") or "").strip()
    if not description: continue
    for artifact in cask.get("artifacts", []):
        if not isinstance(artifact, dict): continue
        for entry in artifact.get("app", []):
            path = entry if isinstance(entry, str) else entry.get("target", "") if isinstance(entry, dict) else ""
            base = os.path.basename(path)
            if base.lower().endswith(".app"): names.setdefault(base[:-4].lower(), description)
        for stanza in ("uninstall", "zap"):
            for directive in artifact.get(stanza, []):
                if isinstance(directive, dict):
                    for identifier in strings(directive.get("quit")): bundles.setdefault(identifier, description)

json.dump({"source": "https://formulae.brew.sh/api/cask.json",
           "generated": datetime.date.today().isoformat(),
           "bundleIdentifiers": dict(sorted(bundles.items())),
           "appNames": dict(sorted(names.items()))},
          open(sys.argv[2], "w"), ensure_ascii=False, indent=0, separators=(",", ":"))
print(f"{len(bundles)} bundle identifiers, {len(names)} app names -> {sys.argv[2]}")
PYTHON

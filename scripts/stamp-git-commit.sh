#!/bin/sh
# Writes the short commit of the checkout into the built product as a resource so Settings › About
# and the Window Peek diagnostics can name the exact build. Runs before code signing, so the file is
# sealed with the bundle.
#
# Xcode's script sandbox denies reading the source tree except for declared input files, so this does
# not run git. It reads the two files the build phase declares: .git/HEAD (a detached commit or a
# branch ref) and .git/logs/HEAD (whose last line ends the newest HEAD commit). CI can pass the
# commit directly through GITHUB_SHA or DD_GIT_COMMIT. Falls back to "unknown".
#
# Output: $TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GitCommit.txt
set -eu
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GitCommit.txt"
git_dir="${SRCROOT}/.git"
commit="${DD_GIT_COMMIT:-${GITHUB_SHA:-}}"
if [ -z "$commit" ] && [ -f "${git_dir}/HEAD" ]; then
    head=$(cat "${git_dir}/HEAD" 2>/dev/null || true)
    case "$head" in
        ref:*)
            if [ -f "${git_dir}/logs/HEAD" ]; then
                commit=$(tail -n 1 "${git_dir}/logs/HEAD" 2>/dev/null | cut -d ' ' -f 2 || true)
            fi
            ;;
        *) commit="$head" ;;
    esac
fi
case "$commit" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) commit=$(printf '%s' "$commit" | cut -c 1-7) ;;
    *) commit=unknown ;;
esac
mkdir -p "$(dirname "$destination")"
printf '%s' "$commit" > "$destination"
echo "Stamped git commit ${commit}"

#!/bin/bash
# Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp
#
# Builds llama.cpp (MIT), Lookout's embedding runtime: the pinned build tag plus scripts/llama.cpp-no-logits.patch
# (copied verbatim from DigUp), as static libraries combined into Vendor/llama/lib/libllamacpp.a, with the headers in
# Vendor/llama/include (all out of git). Lookout/CLlama/module.modulemap exposes those headers to Swift.
#
# Metal shaders are embedded and compiled on first use, so no Metal toolchain is needed. CMake comes from PATH
# (Homebrew's /opt/homebrew/bin is added, because Xcode run-script phases get a minimal PATH), or from a venv in
# Vendor/ (needs uv). Does nothing when that build is already there: the Xcode Run Script phases of LookoutBench and
# LookoutQueryService call it on every build, and the stamp in Vendor/llama/BUILD makes it a no-op.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TAG=b11461   # the first tags with EmbeddingGemma 2 (text + vision + audio) are b11452+
# A new TAG ships only if `LookoutBench reference` passes: it checks this build makes DigUp's reference vectors, so
# every index is kept. If it fails, keep this TAG, or bump LlamaEmbedder.vectorVersion and write new reference
# vectors: every index then embeds again.
PATCH=scripts/llama.cpp-no-logits.patch
SOURCE=Vendor/llama.cpp
OUT=Vendor/llama
# The deployment target is part of the stamp, so changing it rebuilds the libraries.
DEPLOYMENT_TARGET=27.0
STAMP="$TAG $(shasum -a 256 "$PATCH" | cut -c1-12) macOS$DEPLOYMENT_TARGET"
built() { [[ -f "$OUT/lib/libllamacpp.a" && "$(cat "$OUT/BUILD" 2>/dev/null)" == "$STAMP" ]]; }
if built; then
  exit 0
fi
# Several targets run this phase and Xcode may build them in parallel: one builds, the others wait and then find the
# stamp. shlock checks the holder's PID, so a lock left by a killed build doesn't block forever.
mkdir -p Vendor
LOCK=Vendor/.build-llama.lock
until /usr/bin/shlock -f "$LOCK" -p $$; do sleep 1; done
trap 'rm -f "$LOCK"' EXIT
if built; then
  exit 0
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Inside an Xcode build phase these describe the Xcode target, not this CMake build; CMake picks its own SDK.
unset SDKROOT MACOSX_DEPLOYMENT_TARGET ARCHS CC CXX CFLAGS CXXFLAGS LDFLAGS 2>/dev/null || true

if [[ ! -d "$SOURCE" ]]; then
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$SOURCE"
elif [[ "$(git -C "$SOURCE" describe --tags --exact-match 2>/dev/null)" != "$TAG" ]]; then
  git -C "$SOURCE" fetch --quiet --depth 1 origin tag "$TAG"
  git -C "$SOURCE" checkout --quiet --force "$TAG"   # --force also drops the old patch
fi
# Without the patch, every input token costs 1 MiB of logits that an embedding model never produces (262k vocabulary).
# Only a patch that reverses cleanly counts as applied. Anything else (an older patch, a half-applied one, other edits)
# starts over from the pinned tag, and a patch that won't apply there fails the build before anything is stamped.
if ! git -C "$SOURCE" apply --reverse --check "../../$PATCH" 2>/dev/null; then
  git -C "$SOURCE" checkout --quiet --force "$TAG"
  git -C "$SOURCE" clean --quiet -d --force
  if ! git -C "$SOURCE" apply "../../$PATCH"; then
    echo "error: $PATCH doesn't apply to llama.cpp $TAG in $SOURCE. Update the patch for this tag." >&2
    exit 1
  fi
fi

if ! command -v cmake > /dev/null; then
  if [[ ! -x Vendor/cmake-venv/bin/cmake ]]; then
    uv venv --quiet Vendor/cmake-venv --python 3.12
    uv pip install --quiet --python Vendor/cmake-venv/bin/python cmake ninja
  fi
  export PATH="$PWD/Vendor/cmake-venv/bin:$PATH"
fi
GENERATOR=$(command -v ninja > /dev/null && echo Ninja || echo "Unix Makefiles")
# Only the libraries: no tools, no server, nothing downloaded at build time. arm64 only: macOS 27 runs on Apple silicon.
cmake -S "$SOURCE" -B Vendor/llama-build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF -DLLAMA_BUILD_MTMD=ON \
  -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF -DLLAMA_OPENSSL=OFF > /dev/null
cmake --build Vendor/llama-build --config Release -j "$(sysctl -n hw.ncpu)" --target llama mtmd > /dev/null

B=Vendor/llama-build
mkdir -p "$OUT/lib" "$OUT/include"
xcrun libtool -static -no_warning_for_no_symbols -o "$OUT/lib/libllamacpp.a" \
  $B/src/libllama.a $B/tools/mtmd/libmtmd.a $B/ggml/src/libggml.a $B/ggml/src/libggml-base.a \
  $B/ggml/src/libggml-cpu.a $B/ggml/src/ggml-metal/libggml-metal.a $B/ggml/src/ggml-blas/libggml-blas.a \
  $B/vendor/hash/libvendor-hash.a
cp "$SOURCE/include/llama.h" "$SOURCE"/ggml/include/*.h "$SOURCE/tools/mtmd/mtmd.h" "$SOURCE/tools/mtmd/mtmd-helper.h" \
  "$OUT/include/"
# The build, for logs (indexes record LlamaEmbedder.vectorVersion, not this). DigUp touches the Swift file that reads
# this header because SwiftPM misses header changes; Xcode tracks the clang module's headers, so that isn't needed here.
printf '// Written by scripts/build-llama.sh.\n#define LLAMA_BUILD_TAG "%s"\n' "$TAG" > "$OUT/include/llama-build.h"
echo "$STAMP" > "$OUT/BUILD"
echo "Built llama.cpp $TAG (patched) into $OUT"

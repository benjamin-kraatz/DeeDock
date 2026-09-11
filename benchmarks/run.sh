#!/bin/zsh
# Runs the DDock benchmark suite and writes benchmarks/RESULTS.md, results/latest.json, and results/latest.svg.
# See benchmarks/README.md. Usage:
#   benchmarks/run.sh [--quick] [--app /Applications/DDock.app] [--runs N] [--quit-running]
#                     [--skip-launch] [--skip-scenarios] [--skip-e2e] [--skip-idle] [--skip-micro] [--strict]
set -euo pipefail

ROOT=${0:A:h:h}
BENCH="$ROOT/benchmarks"
BUILD="$BENCH/.build"
BUNDLE_ID="de.benjaminkraatz.DeeDock"

APP=""; RUNS=3; LAUNCHES=10; ITERATIONS=200; E2E_ITERATIONS=100; IDLE_SECONDS=600; SETTLE_SECONDS=60
QUIT_RUNNING=0; STRICT=""; SKIP=()
while (( $# )); do
  case "$1" in
    --quick) RUNS=1; LAUNCHES=3; ITERATIONS=30; E2E_ITERATIONS=15; IDLE_SECONDS=60; SETTLE_SECONDS=15 ;;
    --app) APP="$2"; shift ;;
    --runs) RUNS="$2"; shift ;;
    --quit-running) QUIT_RUNNING=1 ;;
    --strict) STRICT="--strict" ;;
    --skip-*) SKIP+=("${1#--skip-}") ;;
    *) echo "Unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
skipped() { (( ${SKIP[(Ie)$1]} )); }

# Two DDocks would draw two docks and fight over the same preferences.
WAS_RUNNING=0
if pgrep -xq DDock; then
  if (( ! QUIT_RUNNING )); then
    echo "DDock is running. Quit it first, or pass --quit-running to quit it now and reopen it afterwards." >&2
    exit 2
  fi
  WAS_RUNNING=1
  osascript -e "tell application id \"$BUNDLE_ID\" to quit"
  while pgrep -xq DDock; do sleep 0.5; done
fi
reopen() { (( WAS_RUNNING )) && open -b "$BUNDLE_ID" || true; }
trap reopen EXIT

if [[ -z "$APP" ]]; then
  echo "Building DDock (Release)…"
  xcodebuild -project "$ROOT/DeeDock.xcodeproj" -scheme DeeDock -configuration Release \
    -derivedDataPath "$BUILD/DerivedData" build -quiet
  APP="$BUILD/DerivedData/Build/Products/Release/DDock.app"
fi
EXECUTABLE="$APP/Contents/MacOS/DDock"
[[ -x "$EXECUTABLE" ]] || { echo "No DDock executable at $EXECUTABLE" >&2; exit 2; }

echo "Building ddock-bench…"
SHARED="$ROOT/DeeDock/App/Diagnostics/Benchmark"
xcrun swiftc -O -swift-version 5 -o "$BUILD/ddock-bench" "$BENCH"/Sources/*.swift \
  "$SHARED/BenchmarkStatistics.swift" "$SHARED/BenchmarkReport.swift" "$SHARED/ProcessResourceUsage.swift"

RUN="$BUILD/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD)
[[ -n "$(git -C "$ROOT" status --porcelain -- DeeDock)" ]] && COMMIT="$COMMIT-dirty"
echo "Stage results: $RUN"
echo "Don't use the Mac while the benchmark runs: the pointer, focus, and idle time all affect the numbers."

# Launches DDock in benchmark mode and waits for it to write its report and quit.
bench() { "$EXECUTABLE" -DDockBenchmark "$@" >/dev/null 2>&1; }

if ! skipped launch; then
  echo "Launch: $LAUNCHES launches…"
  for i in $(seq 1 "$LAUNCHES"); do
    bench launch -DDockBenchmarkOutput "$RUN/launch-$i.json"
    sleep 2
  done
fi

if ! skipped scenarios; then
  for i in $(seq 1 "$RUNS"); do
    echo "Scenarios: run $i of $RUNS, $ITERATIONS iterations each…"
    bench scenarios -DDockBenchmarkOutput "$RUN/scenarios-$i.json" -DDockBenchmarkIterations "$ITERATIONS"
    sleep 3
  done
fi

if ! skipped e2e; then
  echo "End-to-end input…"
  rm -f "$RUN/geometry.json"
  "$EXECUTABLE" -DDockBenchmark e2e -DDockBenchmarkOutput "$RUN/e2e.json" \
    -DDockBenchmarkGeometry "$RUN/geometry.json" >/dev/null 2>&1 &
  APP_PID=$!
  if ! "$BUILD/ddock-bench" e2e --geometry "$RUN/geometry.json" --iterations "$E2E_ITERATIONS"; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  wait "$APP_PID" || true
  sleep 3
fi

if ! skipped idle; then
  echo "Idle: settling for ${SETTLE_SECONDS}s, then sampling DDock and the macOS Dock for ${IDLE_SECONDS}s…"
  "$EXECUTABLE" >/dev/null 2>&1 &
  APP_PID=$!
  sleep "$SETTLE_SECONDS"
  "$BUILD/ddock-bench" sample --seconds "$IDLE_SECONDS" --out "$RUN/idle.json" \
    --process "ddock=$APP_PID" --process "dock=$(pgrep -x Dock)"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" || kill "$APP_PID"
  wait "$APP_PID" || true
fi

if ! skipped micro; then
  echo "Micro benchmarks…"
  python3 "$BENCH/micro/launcher-search.py" --json "$RUN/micro-launcher-search.json"
fi

"$BUILD/ddock-bench" report --run "$RUN" --commit "$COMMIT" --budgets "$BENCH/budgets.json" --out "$BENCH" $STRICT

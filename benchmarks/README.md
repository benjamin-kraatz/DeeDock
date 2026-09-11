# Benchmarks

One command measures DDock's memory, CPU, wakeups, and response times, and writes the published numbers:

```sh
benchmarks/run.sh --app /Applications/DDock.app --quit-running
```

It writes three files:

- `benchmarks/RESULTS.md`: full tables, machine details, and budget results.
- `benchmarks/results/latest.json`: the merged numbers, for the landing page. A dated copy is kept next to it.
- `benchmarks/results/latest.svg`: the summary chart used in the README. It follows the reader's light or dark appearance.

A full run takes about 45 minutes, most of it three passes of the scenarios. `--quick` finishes in about 5 minutes and is for checking the pipeline, not for publishing. Use `--skip-<stage>` to leave a stage out.

## Before a run you intend to publish

- Benchmark the notarized build people download (`--app /Applications/DDock.app`). Without `--app`, the script builds Release into `benchmarks/.build`. macOS treats that copy as a different app, so it doesn't have your Accessibility or Screen Recording grants, and Window Peek is skipped.
- Plug in, turn off Low Power Mode, close Xcode and other busy apps, and wait until Spotlight indexing has finished.
- Don't touch the Mac during the run. The scenarios hold the dock open and drive it themselves. The end-to-end stage moves the real pointer, and the idle stage needs a quiet machine.
- Quit the DDock you use every day, or pass `--quit-running`. The script reopens it at the end.
- The end-to-end stage posts real input, which needs Accessibility access for your terminal. The script checks for it and stops with instructions. It never changes privacy settings. Use `--skip-e2e` to run without it.

Benchmarks use your real dock configuration and change no settings. Pin count, icon size, magnification, auto-hide, and the reveal delay are recorded in the results, because they change what the numbers mean.

## Stages

| Stage | What runs | What it measures |
|---|---|---|
| launch | 10 launches with `-DDockBenchmark launch` | Kernel process start to the first dock panel committed |
| scenarios | 3 runs of `-DDockBenchmark scenarios`, 200 iterations per interaction | Magnification updates, folder stacks, Window Peek, Launcher open, typed Launcher queries and ranking, window search, frame pacing, and DDock's footprint while busy |
| e2e | `-DDockBenchmark e2e` while `ddock-bench e2e` posts real HID events | Pointer to magnified frame, activation zone to revealed dock (with auto-hide on), click to Launcher first frame |
| idle | A normal launch that settles for 60 s, then 10 minutes of sampling | DDock and the macOS Dock sampled together once per second: footprint, CPU, wakeups, and energy |
| micro | `micro/launcher-search.py` | The production ranker on a synthetic 10,000-app index |

`micro/suggestions-model.swift` is the Core ML suggestion prototype. It prints model-quality numbers and isn't part of `run.sh`. See [LAUNCHER-SUGGESTIONS-MODEL.md](../docs/LAUNCHER-SUGGESTIONS-MODEL.md).

## How the numbers are made

- **Where an interval ends.** Response times stop when Core Animation commits the resulting frame to the render server, not when a method returns. `PerformanceSignposts` uses a run-loop observer ordered after Core Animation's own commit. It doesn't include the render server's composite or the display's scan-out, which usually add one or two frames before the change is visible.
- **Input timing.** End-to-end metrics start at the hardware timestamp of the event that caused them, so they include event delivery to DDock. Only pointer movement starts hover and reveal timing. A key press that happens to reveal the dock doesn't count.
- **Percentiles.** Nearest-rank percentiles on raw samples, so every reported value was actually observed. The first 5 iterations of each scenario are warm-up and not recorded.
- **Repeated runs.** Percentiles are never averaged across runs. When a stage runs more than once, `RESULTS.md` shows the run with the median p50, plus the range of p50s as the spread.
- **Frame pacing.** A display link on the dock records callback intervals during the magnification sweep and the Launcher loop. A callback more than 1.5 frames late counts as a hitch. The hitch ratio is the excess time per second: under 5 ms/s is good, and over 10 ms/s is noticeable. This covers main-thread stalls. For render-server hitches, record the same run with Instruments' Animation Hitches template.
- **Idle cost.** `proc_pid_rusage` supplies `ri_phys_footprint`, which Activity Monitor shows as Memory. CPU time is converted from Mach ticks. Wakeups are package-idle plus interrupt wakeups. Both docks are sampled in the same window, so they see the same conditions.

## Budgets

`budgets.json` lists the limits `run.sh` checks against. Pass `--strict` to exit non-zero when a measured value is over its limit. The initial limits are engineering targets, not measured baselines. Adjust them after the first full run on a reference machine.

## Profiling one interaction

Every interval is also an `OSSignposter` interval in the Points of Interest category, so a normal DDock run can be profiled with no benchmark flags:

```sh
xcrun xctrace record --template 'Time Profiler' --attach DDock --time-limit 30s
```

Open the trace, add the Points of Interest instrument, and select an interval to see the call stacks inside it.

## Pieces

- `DeeDock/App/Diagnostics/PerformanceSignposts.swift`: interval names and the commit-timed end markers. Signposts cost a few flag checks when nothing is recording.
- `DeeDock/App/Diagnostics/Benchmark/`: the in-app runner, scenarios, and recorder. A normal launch never creates them. The report schema, statistics, and resource sampling here are also compiled into `ddock-bench`.
- `benchmarks/Sources/`: `ddock-bench` sampling, end-to-end input, report, and chart generation.
- `benchmarks/run.sh`: builds the tools and runs the stages in order.

To add a metric, add a `PerformanceMetric` case, begin and end it at the point the user actually sees the result, give it a title and note in `benchmarks/Sources/Markdown.swift`, and add a budget if it has one.

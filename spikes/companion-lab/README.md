# Companion lab (throwaway)

Reference code for the window companion spike. Never merge it into `main`. The findings are in [`docs/COMPANION-SPIKE.md`](../../docs/COMPANION-SPIKE.md).

- `lab/` is the interactive prototype. Build it with `lab/build.sh` and run `lab/CompanionLabBin` from T3 Code's terminal, which already holds Accessibility and Screen Recording.
- `probes/` holds single-file `swiftc` measurements: inventory, SkyLight events, drag latency, content access, Chromium accessibility, Foundation Models, AX replace, tab lag, focus routing, and the end-to-end run. `target.swift` is the throwaway window that the input-posting probes act on.
- The PNGs are lab screenshots from 2026-10-24.

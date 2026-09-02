# Project skills

These skills are installed in `.agents/skills` so they travel with DeeDock. Codex discovers repository skills there; see the [official skill documentation](https://learn.chatgpt.com/docs/build-skills). They should be available on the next turn. If they do not appear, reopen the task or restart Codex.

| Skill | Purpose | Upstream |
| --- | --- | --- |
| `swiftui-expert-skill` | SwiftUI state, views, animation, accessibility, macOS-specific scenes, and performance | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) |
| `swift-concurrency` | Actor isolation, task lifetime, cancellation, async events, and Swift concurrency diagnostics | [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) |
| `swift-testing-expert` | Focused Swift Testing coverage for geometry, configuration, and behavior models | [AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill) |

Installed on 2026-09-02 from pinned commit revisions. The exact repository, revision, upstream folder, and license are recorded in [sources.json](../.agents/skills/sources.json). Each skill includes its upstream MIT license. These licenses apply to the vendored skill material; they do not select a license for DeeDock.

Use a skill when its scope matches the task, and load only relevant references. The SwiftUI skill includes macOS guidance, but AppKit windowing and Dock integration still require direct Apple API research and runtime evidence. The testing skill is guidance for test design, not permission to run tests; follow `AGENTS.md`.

## Updating

Updates are deliberate, not automatic:

1. Choose and inspect an upstream revision, including instruction and helper-script changes.
2. Use the Codex `skill-installer` helper with the manifest's repository and path, an explicit `--ref` commit, and a temporary `--dest` folder. The installer refuses to overwrite an existing skill.
3. Compare the downloaded directory with the installed copy. Replace it only as part of the requested update, and carry over the upstream license from that same revision.
4. Update `sources.json` and inspect the resulting diff. Preserve any intentional local changes rather than overwriting them silently.

The installed skill content is upstream material, with root license files copied into each skill folder. No app libraries, services, or package-manager dependencies were added.

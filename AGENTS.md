# DeeDock contributor guidance

## Product intent

DeeDock is a native macOS Dock alternative. Read `README.md` first. Match the system Dock's familiarity, visual quality, interaction, and responsiveness, then add precise configuration for displays, positioning, activation zones, size, fade, and behavior.

Treat look, behavior, and feel as separate acceptance criteria. A visually similar row of icons alone does not satisfy the product goal.

## Current scope

The repository is at the setup stage. Do not begin the proposed first slice until the user asks to start implementation. Once a slice is authorized, carry it through without asking for repeated approval of routine, reversible implementation choices.

Keep future features clearly labeled as planned. Do not silently substitute simpler behavior for an agreed requirement or expand a small slice into the entire settings system.

## Native implementation

- Keep Swift and the existing Xcode project. Do not introduce Electron, a web view UI, a parallel SwiftPM app scaffold, or third-party frameworks without a concrete need.
- Use SwiftUI for views and Settings; use AppKit where desktop windowing, focus, pointer events, or OS integration require it. A dock panel is a valid reason to use AppKit.
- Separate placement calculations, configuration, and visibility transitions from views and platform event plumbing. Create abstractions when they have a real consumer; avoid speculative frameworks and empty module trees.
- Inspect actual Xcode build settings before giving language-mode or concurrency advice. Do not assume a new Xcode project uses Swift 6 mode.
- Keep UI and AppKit mutations on the main actor. Keep expensive work out of pointer and rendering paths, and make task ownership and cancellation explicit.
- Prefer system notifications and scoped event handling over continuous polling. Remove observers, event monitors, timers, and tasks when their owner or display goes away.
- Prefer public Apple APIs. Record an API limitation or permission requirement when discovered; do not claim complete system Dock parity without evidence.

## Dock-specific engineering

- Model display identity separately from screen-array order. Handle unplug/replug and rearrangement without losing user configuration.
- Be explicit about coordinate spaces, points versus pixels, backing scale, negative screen origins, and full versus visible screen frames. Do not assume the primary display starts the arrangement at its lower-left corner.
- Treat each display's dock configuration and runtime state independently while allowing shared defaults. Avoid a singleton window assumption that prevents multiple docks later.
- Keep activation-zone geometry separate from visible dock geometry. Model hide/reveal transitions and cancel stale delayed actions when pointer state changes.
- Hover must not steal focus. Make app activation, menus, dragging, and keyboard interaction deliberate and consistent with native behavior.
- Consider Spaces, full-screen apps, display changes, and sleep/wake when touching window lifecycle or positioning. Report which scenarios were actually exercised.
- Prefer real application icons and native materials. Avoid approximating a native effect with hard-coded decoration before checking the platform capability and intended visual reference.
- Include accessible labels and actions, keyboard operation where relevant, and Reduce Motion/Reduce Transparency behavior in the feature design.
- Do not change the user's system Dock preferences, Accessibility grants, login items, or other machine settings merely to make development easier. Any replacement/coexistence flow must be explicit and reversible.

## Skills

Read only the relevant installed skill and references for the task:

| Skill | Location | Use for |
| --- | --- | --- |
| SwiftUI Expert | `.agents/skills/swiftui-expert-skill/SKILL.md` | State, composition, native views, animation, accessibility, rendering performance |
| Swift Concurrency | `.agents/skills/swift-concurrency/SKILL.md` | Actor isolation, tasks, cancellation, event streams, Sendable diagnostics |
| Swift Testing | `.agents/skills/swift-testing-expert/SKILL.md` | Meaningful model/geometry/state tests and async test design |

Project instructions and explicit user requests take precedence over third-party skill advice. In particular, a skill's suggested build/test loop does not authorize running tests. Check API availability against the project's actual SDK and deployment target; a skill is not authoritative SDK documentation.

Keep upstream skill files intact. Sources and licenses are recorded in `.agents/skills/sources.json` and described in `docs/SKILLS.md`. Do not bulk-install unrelated skills or execute bundled helper scripts just because they are present.

## Validation and delivery

- Do not run tests, full verification suites, or automated visual tests unless the user explicitly asks. This includes tests suggested by installed skills. Report what was and was not run.
- For setup or documentation edits, inspect the diff, links, and file structure. Do not build or launch the app solely to validate prose.
- When implementation warrants a build, use the narrow relevant Xcode target and report the exact result. A successful build proves compilation, not native interaction quality.
- When adding tests as part of an agreed feature, focus on behavior that can regress: display placement, activation-zone boundaries, visibility transitions, configuration persistence, and lifecycle cancellation. Avoid tests that merely repeat implementation details.
- Hands-on acceptance should cover the relevant display arrangement, focus behavior, appearance, and OS interactions. State limitations honestly when a scenario cannot be exercised.
- Preserve existing staged and unstaged work. Never reset, stash, switch, or rewrite unrelated changes.
- Do not stage, commit, or push unless requested. Use Conventional Commits when a commit is authorized, and the `codex/` prefix for new branches unless the user specifies another name.
- Keep changes focused. Do not add a release pipeline, signing changes, entitlements, dependencies, or a license for DeeDock itself as incidental setup work.

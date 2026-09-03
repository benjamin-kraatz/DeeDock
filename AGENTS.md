# DeeDock contributor guidance

## Product intent

DeeDock is a native macOS Dock alternative. Read `README.md` first. Match the system Dock's familiarity, visual quality, interaction, and responsiveness, then add precise configuration for displays, positioning, activation zones, size, fade, and behavior.

Treat look, behavior, and feel as separate acceptance criteria. A visually similar row of icons alone does not satisfy the product goal.

## Current scope

The native dock, per-monitor profiles, position/appearance settings, and auto-hide/activation-zone slice with ten animation styles are implemented. Pause for user review after slice 3; further behavior and roadmap features require a new request. Read `docs/ACCEPTANCE.md` for its validation status and limitations. Work on the user’s requested slice; do not automatically begin the remaining customization roadmap. Once a slice is authorized, carry it through without asking for repeated approval of routine, reversible implementation choices.

Keep future features clearly labeled as planned. Do not silently substitute simpler behavior for an agreed requirement or expand a small slice into the entire settings system.

## Native implementation

- Keep Swift and the existing Xcode project. Do not introduce Electron, a web view UI, a parallel SwiftPM app scaffold, or third-party frameworks without a concrete need.
- Use SwiftUI for views and Settings; use AppKit where desktop windowing, focus, pointer events, or OS integration require it. A dock panel is a valid reason to use AppKit.
- Separate placement calculations, configuration, and visibility transitions from views and platform event plumbing. Create abstractions when they have a real consumer; avoid speculative frameworks and empty module trees.
- Inspect actual Xcode build settings before giving language-mode or concurrency advice. Do not assume a new Xcode project uses Swift 6 mode.
- Keep UI and AppKit mutations on the main actor. Keep expensive work out of pointer and rendering paths, and make task ownership and cancellation explicit.
- Prefer system notifications and scoped event handling over continuous polling. Remove observers, event monitors, timers, and tasks when their owner or display goes away.
- Keep all app-owned UI copy in `DeeDock/Resources/Localizable.xcstrings`, with stable keys, generated Swift symbols, and translator comments. Use Pin/Unpin terminology. Preserve localization for conditional accessibility text and interpolated errors; do not translate app names supplied by macOS.
- Prefer public Apple APIs. Record an API limitation or permission requirement when discovered; do not claim complete system Dock parity without evidence.

## File and component organization

- Keep each file focused on one coherent responsibility. Split large files when they combine independently understandable views, models, services, or lifecycle logic; do not keep growing an all-in-one file.
- Split SwiftUI views into the smallest useful components with clear names, inputs, and responsibilities. Prefer dedicated view types for independently meaningful UI pieces over a large `body` or a collection of substantial view-building methods in one file. Do not extract trivial wrappers that add no clarity.
- Group files into real filesystem folders by feature or responsibility. Keep feature-specific views, models, and supporting code together; move genuinely shared code into clearly named shared folders. Avoid a flat source directory, vague catch-all folders, and empty speculative hierarchies.
- When moving or splitting files, update references and Xcode target membership so the project remains coherent. Keep unrelated reorganizations outside the requested change.

## SwiftUI previews

- Add `#Preview` declarations when they help inspect a view's appearance, states, or interaction. Include useful states such as pinned/running/unavailable apps, empty content, and errors where relevant; avoid redundant previews for trivial wrappers.
- Keep previews near the view they demonstrate. Use deterministic sample data and lightweight injected dependencies. Previews must not launch applications, modify real preferences, request permissions, or depend on live workspace state.
- Use preview variants for meaningful layout and accessibility differences, such as longer translated text, light/dark appearance, and Reduce Motion or Reduce Transparency, when the view is affected.

## Swift documentation and comments

- Add Swift documentation comments (`///`, compatible with DocC) to exported and public types, initializers, properties, and methods. Document internal interfaces used across components when their contract is not obvious. Do not widen access control solely to document a member.
- Explain purpose and observable behavior, including parameters, return values, thrown errors, side effects, and actor or lifecycle requirements where relevant. Document constraints and invariants instead of repeating the declaration in prose.
- Comment critical or non-obvious logic where it lives, especially coordinate conversions, stable animation geometry, focus handling, event-monitor ownership, cancellation, and persistence behavior. Explain why the approach is needed and what must remain true.
- Keep documentation and comments accurate when behavior changes. Remove stale explanations and avoid narrating self-evident code.

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
| How | `.agents/skills/how/SKILL.md` | Architecture walkthroughs and placement questions |
| Why | `.agents/skills/why/SKILL.md` | Design rationale and historical evidence |
| Interrogate | `.agents/skills/interrogate/SKILL.md` | Multi-model adversarial review of a diff |
| Unslop | `.agents/skills/unslop/SKILL.md` | Cutting AI tells from writing |
| Technical writing | `.agents/skills/technical-writing/SKILL.md` | Docs, RFCs, READMEs, PRs, and commit messages |
| Writing for agents | `.agents/skills/writing-for-agents/SKILL.md` | Skills, `AGENTS.md`, and other agent-consumed docs |

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

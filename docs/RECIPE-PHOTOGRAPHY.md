# Recipe photography

DEE-67 adds **Snapshot workspace…** to **Settings → Modes**. It creates an editable draft from running apps, visible window metadata, and the active mode's DDock pins.

## Draft and save

The draft freezes the active mode's per-display pins and App Visibility before window discovery starts. It includes remembered disconnected displays and session-only display configurations. The source mode's existing recipe is not copied.

Running apps appear first, sorted by name. Pins follow in display-ID and pin order. Multiple running instances, visible windows, and app pins share one recipe choice per application identity. Pinned folders share one choice per standardized saved path. Folder steps reuse the existing bookmark. Empty or oversized folder bookmarks produce a notice and can be added through the editor's native file picker.

The first 12 choices are selected. Every additional choice remains visible, and removing a step makes room for another. The existing recipe editor supports adding apps, files, folders, explicit web links, and Shortcuts, plus repair, removal, and reordering. Selection changes the recipe only. The captured pin layout remains intact.

**Save as new mode** requires a nonempty, unique name and at least one validly encoded recipe step. It saves the new mode and recipe in one repository write. Save failures leave the draft open. Cancel discards the draft. Neither action activates a mode, launches an app, nor runs a Shortcut. The active and previous mode IDs stay unchanged.

## Window context and public APIs

App discovery uses the existing `ApplicationServicing` implementation backed by `NSWorkspace.runningApplications`. DDock excludes its own running entry. Pin discovery reads DDock's mode store and never reads or changes system Dock preferences.

Window discovery calls `WindowContextCapturing.discover()` through the shared `ScreenCaptureWindowContextService`. Its public ScreenCaptureKit API returns eligible onscreen windows with titles and owner identities. The service excludes desktop windows, DDock's windows, and nonzero window layers. Eligible windows must be wider than 80 points and taller than 60 points. See Apple's [shareable-content API](https://developer.apple.com/documentation/screencapturekit/scshareablecontent/getexcludingdesktopwindows(_:onscreenwindowsonly:completionhandler:)).

The operation checks existing Screen Recording access and does not request permission. Without access, or if discovery fails, apps and pins remain usable. No eligible windows is a separate state. A new snapshot is needed after granting access. The sheet owns the discovery task, and canceled results cannot update a dismissed draft.

This feature never calls screenshot capture or OCR. Window titles appear under their app for review and remain only in the draft's memory. Saving or canceling discards them. A title is not treated as a file path, browser URL, or instruction. Hidden, minimized, other-Space, and small windows are not a complete desktop inventory. Visible full-screen windows depend on what macOS exposes at discovery time.

## Relationship to DEE-21

[DEE-67](https://linear.app/d-zwei/issue/DEE-67/recipe-photography-snapshot-draft-recipe) owns capture and draft review. [DEE-21 and GitHub issue 35](https://github.com/benjamin-kraatz/DeeDock/issues/35) own the saved recipe format and explicit **Prepare Workspace** execution.

The snapshot becomes the existing `WorkspaceRecipe` on a new `DockMode`, with no new persistence schema or playback engine. Window choices reopen the owning app. They do not restore specific windows, window positions, Spaces, browser tabs, or unsaved documents. Files and links require explicit editor input. Ordinary mode switching keeps its existing behavior.

Validation and pending native scenarios are recorded in [acceptance notes](ACCEPTANCE.md#dee-67-recipe-photography).

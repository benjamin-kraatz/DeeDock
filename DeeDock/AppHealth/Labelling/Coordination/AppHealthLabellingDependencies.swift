import AppKit

/// The services `AppHealthLabellingCoordinator` uses. `live()` wires the panels and system services; tests inject
/// fakes so prompts, timers, and writes can be exercised without windows or real waits.
struct AppHealthLabellingDependencies {
    var now: @MainActor () -> Date
    /// Waits for a question's timer. Throws when the timer is cancelled.
    var sleep: @Sendable (Duration) async throws -> Void
    /// A number in `0..<1` for the ordinary-prompt draw.
    var random: @Sendable () -> Double
    /// DOKK's own bundle identifier, never asked about.
    var ownBundleID: String?
    /// Names and icons from macOS for bundle identifiers.
    var appDisplays: @MainActor ([String]) -> [String: AppHealthAppDisplay]
    /// Speaks a VoiceOver announcement without moving focus.
    var announce: @MainActor (String) -> Void
    /// Puts a prompt on screen. The closure re-reads the anchor after display changes.
    var presentPrompt: @MainActor (AppHealthLabelSession, AppHealthAnchor,
                                   @escaping @MainActor () -> AppHealthAnchor?) -> any AppHealthPromptPresenting
    /// Opens the manual picker with the latest tick's apps, busiest first.
    var presentPicker: @MainActor ([AppHealthPickerEntry]) -> any AppHealthPickerPresenting

    /// The production services.
    static func live() -> AppHealthLabellingDependencies {
        AppHealthLabellingDependencies(
            now: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            random: { Double.random(in: 0..<1) },
            ownBundleID: Bundle.main.bundleIdentifier,
            appDisplays: { AppHealthAppDisplay.running($0) },
            announce: { message in
                NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
            },
            presentPrompt: { session, anchor, reanchor in
                let panel = AppHealthPromptPanelController(session: session, anchor: anchor, reanchor: reanchor)
                panel.show()
                return panel
            },
            presentPicker: { entries in
                let picker = AppHealthPickerPanelController(entries: entries)
                picker.present()
                return picker
            })
    }
}

extension AppHealthAppDisplay {
    /// Names and icons for running apps, as macOS reports them (`localizedName`, never translated by DOKK).
    /// Apps that are no longer running fall back to a Launch Services lookup.
    static func running(_ bundleIDs: [String]) -> [String: AppHealthAppDisplay] {
        var running: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, running[id] == nil else { continue }
            running[id] = app
        }
        var displays: [String: AppHealthAppDisplay] = [:]
        for id in bundleIDs {
            if let app = running[id], let name = app.localizedName {
                displays[id] = AppHealthAppDisplay(bundleID: id, name: name, icon: app.icon)
            } else {
                displays[id] = .live(id)
            }
        }
        return displays
    }
}

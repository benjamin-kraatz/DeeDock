import AppKit
import ApplicationServices

/// Asks Electron and Chromium apps for their web accessibility tree, only when Robi needs it.
///
/// Both build that tree lazily, for assistive apps only. Electron honours `AXManualAccessibility`,
/// which has no side effects. Chromium browsers need `AXEnhancedUserInterface`: the spike saw it
/// open Helium's page (43 → 1,303 elements) even though the call returns -25208. Rectangle and
/// Hammerspoon document that the flag can disturb window animations and costs Chromium extra work,
/// so Robi sets it only for an explicit whole-window or selection request and restores it on dismiss.
enum RobiWebAccessibility {
    /// What was switched on, so it can be switched off again.
    enum Change {
        case none
        case enhancedInterface(pid_t)
    }

    /// Turns on the web tree for the app if it is Electron or Chromium based.
    static func enable(for application: NSRunningApplication) -> Change {
        let pid = application.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        if AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success { return .none }
        guard isChromium(application.bundleURL) else { return .none }
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return .enhancedInterface(pid)
    }

    static func restore(_ change: Change) {
        guard case let .enhancedInterface(pid) = change else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    }

    /// Chromium-based apps ship `chrome_100_percent.pak` inside their framework. Cached per bundle.
    private static var chromiumBundles: [URL: Bool] = [:]

    private static func isChromium(_ bundle: URL?) -> Bool {
        guard let bundle else { return false }
        if let known = chromiumBundles[bundle] { return known }
        let frameworks = bundle.appending(path: "Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        let found = names.contains { name in
            name.hasSuffix(".framework") && FileManager.default.fileExists(
                atPath: frameworks.appending(path: "\(name)/Resources/chrome_100_percent.pak").path)
        }
        chromiumBundles[bundle] = found
        return found
    }
}

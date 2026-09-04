import ApplicationServices
import AppKit

/// Permission checks are read-only until the person explicitly requests the system prompt.
@MainActor
protocol WindowAccessServicing: AnyObject {
    var status: WindowAccessStatus { get }
    func requestAccess()
    func openSystemSettings()
}

/// Public Accessibility trust APIs plus a direct link to the matching System Settings pane.
@MainActor
final class SystemWindowAccessService: WindowAccessServicing {
    var status: WindowAccessStatus { AXIsProcessTrusted() ? .enabled : .notEnabled }

    func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

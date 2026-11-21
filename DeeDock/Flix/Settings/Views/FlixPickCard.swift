import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

/// Flix Pick: the switch, a note while DOKK lacks Accessibility permission (Flix Pick stays hidden
/// then; nothing here asks for it), and the apps hidden with **Not in <App>**, each with a button to
/// show Flix Pick there again. The footnote says what is read and kept.
struct FlixPickCard: View {
    @Binding var settings: FlixSettings
    /// Read when the page draws; Settings never requests the permission.
    var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        SettingsCard(title: .flixSettingsPick, footnote: .flixSettingsPickPrivacy) {
            SettingsToggleRow(title: .flixSettingsPickShow, subtitle: .flixSettingsPickHelp, isOn: $settings.showsFlixPick)
            if settings.showsFlixPick, !accessibilityGranted {
                // Quiet, as the web links card's note about the same permission: it explains,
                // it does not warn.
                SettingsStatusRow(symbol: "accessibility", tint: .secondary, message: Text(.flixSettingsPickNeedsAccess))
            }
            ForEach(settings.flixPickExcludedApps, id: \.self) { bundleIdentifier in
                FlixPickExcludedAppRow(bundleIdentifier: bundleIdentifier) {
                    settings.flixPickExcludedApps.removeAll { $0 == bundleIdentifier }
                }
                .disabled(!settings.showsFlixPick)
            }
        }
    }
}

/// One app where Flix Pick is hidden: its icon and name as macOS shows them, and **Show Again**.
/// On the same grid as the page's other list rows.
private struct FlixPickExcludedAppRow: View {
    let bundleIdentifier: String
    let remove: () -> Void

    var body: some View {
        let app = Self.lookUp(bundleIdentifier)
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(.flixSettingsPickHiddenIn(app.name))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            Button(action: remove) { Text(.flixSettingsPickShowAgain) }
                .controlSize(.small)
                .accessibilityLabel(Text(.flixSettingsPickShowAgainIn(app.name)))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(minHeight: SettingsMetrics.rowMinimumHeight)
    }

    /// The app's name and icon from Launch Services; the bundle identifier when it is not installed.
    private static func lookUp(_ bundleIdentifier: String) -> (name: String, icon: NSImage) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return (bundleIdentifier, NSWorkspace.shared.icon(for: .application))
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return (name.hasSuffix(".app") ? String(name.dropLast(4)) : name, NSWorkspace.shared.icon(forFile: url.path))
    }
}

#if DEBUG
#Preview("Flix Pick settings, no Accessibility, two hidden apps") {
    @Previewable @State var settings: FlixSettings = {
        var settings = FlixSettings()
        settings.flixPickExcludedApps = ["com.example.writer", "com.example.importer"]
        return settings
    }()
    FlixPickCard(settings: $settings, accessibilityGranted: false)
        .frame(width: 600)
        .padding()
}

#Preview("Flix Pick settings, German") {
    @Previewable @State var settings = FlixSettings()
    FlixPickCard(settings: $settings, accessibilityGranted: true)
        .frame(width: 600)
        .padding()
        .environment(\.locale, Locale(identifier: "de"))
}
#endif

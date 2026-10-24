import SwiftUI

/// Settings › Windows & Focus › Robi: the switch, the shortcut, how Robi answers, where it hides,
/// and the permissions it needs.
struct RobiSettingsPane: View {
    let store: RobiStore
    /// Nil when Settings has no running dock, such as in previews of the whole page.
    let controller: RobiController?
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController

    var body: some View {
        @Bindable var store = store
        RobiGeneralSettingsCard(settings: $store.settings,
                                accessGranted: windowAccess.status == .enabled,
                                shortcutAvailable: controller?.shortcutAvailable ?? true,
                                requestAccess: windowAccess.requestAccess,
                                checkAgain: windowAccess.refresh,
                                openSystemSettings: windowAccess.openSystemSettings)
            .onAppear { windowAccess.refresh() }
        RobiAnswersSettingsCard(settings: $store.settings,
                                hasKey: store.hasClaudeKey,
                                onDeviceUnavailable: RobiAgent.onDeviceUnavailableReason,
                                saveKey: { store.saveClaudeKey($0) },
                                removeKey: store.removeClaudeKey)
            .disabled(!store.settings.isEnabled)
        RobiExclusionsSettingsCard(excluded: store.settings.excludedBundleIdentifiers,
                                   setExcluded: store.setExcluded)
            .disabled(!store.settings.isEnabled)
        PreviewPermissionsSettingsCard(windowAccess: windowAccess, screenCapture: screenCapture,
                                       footnote: .robiPermissionsHelp)
    }
}

/// The opt-in switch, the Accessibility notice, and the global shortcut.
struct RobiGeneralSettingsCard: View {
    @Binding var settings: RobiSettings
    let accessGranted: Bool
    let shortcutAvailable: Bool
    let requestAccess: () -> Void
    let checkAgain: () -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        SettingsCard(title: .robiSettingsTitle, footnote: .robiSettingsHelp) {
            SettingsToggleRow(title: .robiToggle, subtitle: .robiToggleHelp, isOn: $settings.isEnabled)
            if settings.isEnabled && !accessGranted {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange, message: Text(.robiNeedsAccessibility)) {
                    Button(.windowAccessEnable, action: requestAccess)
                        .buttonStyle(.borderedProminent)
                    SettingsMoreMenu {
                        Button(.windowAccessCheckAgain, action: checkAgain)
                        Button(.windowAccessOpenSettings, action: openSystemSettings)
                    }
                }
            }
            SettingsToggleRow(title: .robiShortcutToggle, subtitle: .robiShortcutToggleHelp, isOn: $settings.shortcutEnabled)
                .disabled(!settings.isEnabled)
            if settings.isEnabled && settings.shortcutEnabled && !shortcutAvailable {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange, message: Text(.robiShortcutConflict))
            }
            SettingsStackedRow {
                Label { Text(.robiPrivacyNote) } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Which model answers, the Anthropic API key for Claude, and Claude's effort.
struct RobiAnswersSettingsCard: View {
    @Binding var settings: RobiSettings
    let hasKey: Bool
    let onDeviceUnavailable: LocalizedStringResource?
    let saveKey: (String) -> Bool
    let removeKey: () -> Void
    @State private var key = ""
    @State private var saveFailed = false

    var body: some View {
        SettingsCard(title: .robiAnswersTitle, footnote: settings.answerModel == .claude ? .robiClaudeHelp : .robiOnDeviceHelp) {
            SettingsPickerRow(title: .robiAnswerWith, options: [
                SettingsOption(value: RobiAnswerModel.onDevice, title: .robiModelOnDevice, symbol: "lock.shield"),
                SettingsOption(value: RobiAnswerModel.claude, title: .robiModelClaude, symbol: "sparkle"),
            ], selection: $settings.answerModel)
            if settings.answerModel == .onDevice, let onDeviceUnavailable {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange, message: Text(onDeviceUnavailable))
            }
            if settings.answerModel == .claude {
                if hasKey {
                    SettingsRow(title: .robiKeySaved, subtitle: .robiKeySavedHelp) {
                        Button(role: .destructive, action: removeKey) { Text(.robiKeyRemove) }
                    }
                } else {
                    SettingsStackedRow(title: .robiKeyTitle, subtitle: .robiKeyHelp) {
                        HStack(spacing: 8) {
                            SecureField(text: $key, prompt: Text(verbatim: "sk-ant-…")) { Text(.robiKeyFieldLabel) }
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(save)
                            Button(action: save) { Text(.robiKeySave) }
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if saveFailed {
                            Text(.robiKeySaveFailed).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                SettingsPickerRow(title: .robiEffort, options: [
                    SettingsOption(value: RobiClaudeEffort.medium, title: .robiEffortMedium, symbol: "gauge.medium"),
                    SettingsOption(value: RobiClaudeEffort.high, title: .robiEffortHigh, symbol: "gauge.high"),
                ], selection: $settings.claudeEffort)
            }
        }
    }

    private func save() {
        saveFailed = !saveKey(key)
        if !saveFailed { key = "" }
    }
}

/// Apps whose windows never get Robi.
struct RobiExclusionsSettingsCard: View {
    let excluded: [String]
    let setExcluded: (String, Bool) -> Void

    var body: some View {
        SettingsCard(title: .robiExclusionsTitle, footnote: .robiExclusionsHelp) {
            if excluded.isEmpty {
                SettingsRow(title: .robiExclusionsEmpty) { EmptyView() }
            }
            ForEach(excluded, id: \.self) { bundle in
                RobiExcludedAppRow(bundleIdentifier: bundle) { setExcluded(bundle, false) }
            }
            SettingsListFooter {
                Menu {
                    ForEach(candidates, id: \.bundleIdentifier) { app in
                        Button {
                            if let bundle = app.bundleIdentifier { setExcluded(bundle, true) }
                        } label: { Text(app.localizedName ?? app.bundleIdentifier ?? "") }
                    }
                } label: {
                    Label { Text(.robiExclusionsAdd) } icon: { Image(systemName: "plus") }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(candidates.isEmpty)
            }
        }
    }

    /// Running regular apps that are not excluded yet, by name. App names come from macOS.
    private var candidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !excluded.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }
}

/// One excluded app with its icon, its name as macOS reports it, and a remove button.
private struct RobiExcludedAppRow: View {
    let bundleIdentifier: String
    let remove: () -> Void

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
                .resizable()
                .frame(width: 20, height: 20)
            Text(verbatim: url.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
                 ?? url?.deletingPathExtension().lastPathComponent ?? bundleIdentifier)
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(.robiExclusionsRemove))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 8)
    }
}

#if DEBUG
private struct RobiSettingsPreview: View {
    @State var settings: RobiSettings
    var access = true
    var hasKey = false

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                RobiGeneralSettingsCard(settings: $settings, accessGranted: access, shortcutAvailable: true,
                                        requestAccess: {}, checkAgain: {}, openSystemSettings: {})
                RobiAnswersSettingsCard(settings: $settings, hasKey: hasKey, onDeviceUnavailable: nil,
                                        saveKey: { _ in true }, removeKey: {})
                RobiExclusionsSettingsCard(excluded: ["com.apple.Terminal"], setExcluded: { _, _ in })
            }
            .padding(24)
            .frame(width: SettingsMetrics.columnWidth)
        }
    }
}

#Preview("Off") { RobiSettingsPreview(settings: RobiSettings()) }

#Preview("On, needs Accessibility") {
    var settings = RobiSettings()
    settings.isEnabled = true
    return RobiSettingsPreview(settings: settings, access: false)
}

#Preview("Claude, no key, dark") {
    var settings = RobiSettings()
    settings.isEnabled = true
    settings.answerModel = .claude
    return RobiSettingsPreview(settings: settings).preferredColorScheme(.dark)
}

#Preview("Claude with key, German") {
    var settings = RobiSettings()
    settings.isEnabled = true
    settings.answerModel = .claude
    settings.claudeEffort = .high
    return RobiSettingsPreview(settings: settings, hasKey: true).environment(\.locale, Locale(identifier: "de"))
}
#endif

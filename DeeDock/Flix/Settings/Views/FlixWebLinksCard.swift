import ApplicationServices
import SwiftUI

/// Web links: off by default, with "pages you read" as a separate opt-in and a list of sites
/// never tracked.
///
/// These are the switches `FlixLinkTracker` obeys. A URL dropped on Flix Files, or a page kept
/// with **Save this page**, is kept either way, because that is a deliberate save. Two notes explain
/// the limits: Safari pages are kept only when saved or downloaded from (Safari's private windows
/// cannot be told apart), and without Accessibility permission only saved pages are kept.
struct FlixWebLinksCard: View {
    @Binding var settings: FlixSettings
    @State private var newSite = ""

    var body: some View {
        SettingsCard(title: .flixSettingsWebLinks, footnote: .flixSettingsWebLinksFootnote) {
            SettingsToggleRow(title: .flixSettingsTrackLinks, subtitle: .flixSettingsTrackLinksHelp,
                              isOn: $settings.tracksLinks)
            SettingsToggleRow(title: .flixSettingsPagesYouRead, subtitle: .flixSettingsPagesYouReadHelp,
                              isOn: $settings.tracksPagesYouRead, disabled: !settings.tracksLinks)
            SettingsToggleRow(title: .flixSettingsSensitiveSites, subtitle: .flixSettingsSensitiveSitesHelp,
                              isOn: $settings.excludesSensitiveSites, disabled: !settings.tracksLinks)
            SettingsToggleRow(title: .flixSettingsSiteIcons, subtitle: .flixSettingsSiteIconsHelp,
                              isOn: $settings.fetchesSiteIcons, disabled: !settings.tracksLinks)
            ForEach(settings.excludedSites, id: \.self) { site in
                HStack {
                    Image(systemName: "nosign").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(verbatim: site)
                    Spacer(minLength: 8)
                    Button { settings.excludedSites.removeAll { $0 == site } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(.flixSettingsRemoveSite(site)))
                }
                .padding(.horizontal, SettingsMetrics.rowInset)
                .frame(minHeight: 34)
            }
            HStack(spacing: 8) {
                TextField(text: $newSite) { Text(.flixSettingsExcludeSitePlaceholder) }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSite)
                Button(action: addSite) { Text(.flixSettingsExcludeSite) }
                    .disabled(FlixWebLinksCard.host(from: newSite) == nil)
            }
            .controlSize(.small)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 10)
            .disabled(!settings.tracksLinks)
            if settings.tracksLinks {
                FlixWebLinksNote(text: .flixSettingsWebLinksSafari, symbol: "safari")
                if !AXIsProcessTrusted() {
                    FlixWebLinksNote(text: .flixSettingsWebLinksAccess, symbol: "accessibility")
                }
            }
        }
    }

    private func addSite() {
        guard let host = Self.host(from: newSite), !settings.excludedSites.contains(host) else { return }
        settings.excludedSites.append(host)
        newSite = ""
    }

    /// The host of a typed site ("https://bank.example.com/login" → "bank.example.com"), lowercased.
    static func host(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: candidate)?.host, host.contains(".") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A quiet note under the web link switches.
private struct FlixWebLinksNote: View {
    let text: LocalizedStringResource
    let symbol: String

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(.secondary) }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.bottom, 10)
    }
}

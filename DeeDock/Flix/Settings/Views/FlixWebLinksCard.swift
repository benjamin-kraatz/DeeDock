import SwiftUI

/// Web links: off by default, with "pages you read" as a separate opt-in and a list of sites
/// never tracked.
///
/// These are the switches phase B1's link tracking obeys. Until it ships they are saved but
/// nothing is tracked; a URL dropped on Flix Files is kept either way, because that is a deliberate
/// save.
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

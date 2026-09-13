import SwiftUI
import UniformTypeIdentifiers

/// Explicit opt-in and a bounded party picker. Choosing an app never launches it.
struct BossFightSettingsView: View {
    let controller: FocusSessionController
    @State private var choosingApps = false

    private var isEnabled: Bool { controller.bossFight.enabled }

    var body: some View {
        SettingsCard(title: .bossFightTitle, footnote: isEnabled ? .bossFightPartyLimit : nil) {
            SettingsToggleRow(title: .bossFightEnable, subtitle: .bossFightHelp,
                              isOn: Binding(get: { isEnabled },
                                            set: { controller.configureBossFight(enabled: $0) }))
            if isEnabled {
                ForEach(controller.bossFight.party) { member in
                    HStack(spacing: 10) {
                        BossFightPartyIcon(member: member, icon: controller.partyIcons[member.id])
                        Text(verbatim: member.name).lineLimit(1)
                        Spacer(minLength: SettingsMetrics.controlSpacing)
                        Button { controller.removePartyApp(member.id) } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(.bossFightRemoveApp(member.name)))
                        .help(Text(.bossFightRemoveApp(member.name)))
                    }
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }
                if controller.bossFight.party.isEmpty {
                    SettingsStatusRow(symbol: "person.2", tint: .secondary, message: Text(.bossFightPartyEmpty))
                }
                SettingsListFooter {
                    Button(.bossFightChooseApps, systemImage: "plus") { choosingApps = true }
                        .disabled(controller.bossFight.party.count >= BossFightConfiguration.maximumPartySize)
                }
            }
        }
        .disabled(controller.requiresReset)
        .fileImporter(isPresented: $choosingApps, allowedContentTypes: [.applicationBundle],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): controller.addPartyApps(urls)
            case .failure(let error):
                guard (error as? CocoaError)?.code != .userCancelled else { return }
                controller.error = String(localized: .bossFightPickerFailed)
            }
        }
    }
}

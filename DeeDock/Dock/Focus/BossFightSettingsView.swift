import SwiftUI
import UniformTypeIdentifiers

/// Explicit opt-in and a bounded party picker. Choosing an app never launches it.
struct BossFightSettingsView: View {
    let controller: FocusSessionController
    @State private var choosingApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(.bossFightEnable, isOn: Binding(get: { controller.bossFight.enabled },
                                                  set: { controller.configureBossFight(enabled: $0) }))
            Text(.bossFightHelp).font(.callout).foregroundStyle(.secondary)
            if controller.bossFight.enabled {
                Text(.bossFightParty).font(.headline)
                ForEach(controller.bossFight.party) { member in
                    HStack {
                        BossFightPartyIcon(member: member, icon: controller.partyIcons[member.id])
                        Text(verbatim: member.name).lineLimit(1)
                        Spacer()
                        Button { controller.removePartyApp(member.id) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel(Text(.bossFightRemoveApp(member.name)))
                        .help(Text(.bossFightRemoveApp(member.name)))
                    }
                }
                if controller.bossFight.party.isEmpty {
                    Text(.bossFightPartyEmpty).font(.callout).foregroundStyle(.secondary)
                }
                Button(.bossFightChooseApps, systemImage: "plus") { choosingApps = true }
                    .disabled(controller.bossFight.party.count >= BossFightConfiguration.maximumPartySize)
                Text(.bossFightPartyLimit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(controller.requiresReset)
        .fileImporter(isPresented: $choosingApps, allowedContentTypes: [.applicationBundle],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): controller.addPartyApps(urls)
            case .failure: controller.error = String(localized: .bossFightPickerFailed)
            }
        }
    }
}

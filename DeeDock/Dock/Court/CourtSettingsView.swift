import SwiftUI

struct CourtSettingsView: View {
    let court: CourtController
    @State private var library = false
    var body: some View {
        SettingsCard(title: .courtTitle, footnote: .courtHelp) {
            VStack(alignment: .leading, spacing: 14) {
                Text(.courtExperiment).font(.callout).foregroundStyle(.secondary)
                Toggle(isOn: Binding(get: { court.enabled }, set: { court.setEnabled($0) })) {
                    Text(.courtEnable)
                }.disabled(court.repository.unavailable)
                Text(.courtConsent).font(.caption).foregroundStyle(.secondary)
                if court.repository.unavailable { Text(.courtStorageFailed).foregroundStyle(.red) }
                if !CourtComposer.available { Text(.courtUnavailable).foregroundStyle(.secondary) }
                HStack {
                    Button(.courtSkipForever) { court.setEnabled(false) }
                    Button(.courtClear) { court.clear() }
                }
                HStack {
                    Button(.courtSample) { court.sample(witness: false) }
                    Button(.courtSampleWitness) { court.sample(witness: true) }
                }.disabled(!CourtComposer.available)
                DisclosureGroup(isExpanded: $library) {
                    Text(.courtFiction).font(.caption).foregroundStyle(.secondary)
                    if court.repository.document.characters.isEmpty { Text(.courtLibraryEmpty) }
                    ForEach(court.repository.document.characters.values.sorted { $0.appName < $1.appName }) { character in
                        DisclosureGroup(character.appName) {
                            CourtBiographyView(character: character)
                            ForEach(court.repository.document.relationships.keys.filter {
                                $0.split(separator: "|").contains(Substring(character.id))
                            }.sorted(), id: \.self) { key in
                                Text(court.repository.document.relationships[key] ?? "").textSelection(.enabled)
                            }
                            ForEach(court.repository.document.cases.filter { $0.participantIDs.contains(character.id) }) { record in
                                VStack(alignment: .leading) {
                                    Text(record.date, style: .date).font(.caption.bold())
                                    Text(record.summary).textSelection(.enabled)
                                }.padding(.vertical, 6)
                            }
                            Button(.courtDeleteCharacter, role: .destructive) { court.deleteCharacter(character.id) }
                        }
                    }
                } label: { Text(.courtLibrary) }
            }
            .padding(.vertical, 8)
        }
    }
}

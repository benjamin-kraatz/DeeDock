import SwiftUI
import UniformTypeIdentifiers

/// Bookmark management for Launcher copy destinations. Removal never deletes folder contents.
struct LauncherFileDestinationsSettingsCard: View {
    let store: LauncherFileDestinationsStore
    @State private var confirmsReset = false
    @State private var renaming: UUID?
    @State private var draftName = ""
    @State private var repairing: UUID?
    @State private var adding = false

    var body: some View {
        SettingsCard(title: .launcherFileDestinationsTitle, footnote: .launcherFileDestinationsHelp) {
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.destinations) { destination in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                if renaming == destination.id {
                                    TextField(text: $draftName) {
                                        Text(.launcherFileDestinationName)
                                    }
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { commitRename(destination.id) }
                                } else {
                                    Text(verbatim: destination.name)
                                    Text(verbatim: destination.url.path)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    if !store.isAvailable(destination) {
                                        Text(.launcherFileDestinationUnavailable)
                                            .font(.caption).foregroundStyle(.red)
                                    }
                                }
                            }
                            Spacer()
                            if renaming == destination.id {
                                Button(.launcherFileDestinationSaveName) { commitRename(destination.id) }
                            } else {
                                Button(.launcherFileDestinationRename) {
                                    renaming = destination.id
                                    draftName = destination.name
                                }
                                .disabled(store.requiresReset)
                            }
                            Button(.launcherFileDestinationRepair) { repairing = destination.id }
                                .disabled(store.requiresReset)
                            Button(.launcherFileDestinationRemove, role: .destructive) {
                                store.remove(destination.id)
                            }
                            .disabled(store.requiresReset)
                        }
                    }
                    if let error = store.error {
                        Text(verbatim: error).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack {
                        Button(.launcherFileDestinationAdd, systemImage: "folder.badge.plus") {
                            adding = true
                        }
                        .disabled(store.requiresReset
                                  || store.destinations.count >= LauncherFileDestinationsDocument.capacity)
                        if store.requiresReset {
                            Button(.launcherFileDestinationsReset, role: .destructive) { confirmsReset = true }
                        }
                    }
                }
            }
        }
        .confirmationDialog(.launcherFileDestinationsReset, isPresented: $confirmsReset) {
            Button(.launcherFileDestinationsReset, role: .destructive) { store.reset() }
        } message: { Text(.launcherFileDestinationsResetHelp) }
        .fileImporter(isPresented: Binding(
            get: { adding || repairing != nil },
            set: { if !$0 { adding = false; repairing = nil } }
        ), allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private func commitRename(_ id: UUID) {
        store.rename(id, to: draftName)
        renaming = nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        let target = repairing
        let isAdding = adding
        repairing = nil
        adding = false
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if !isAdding, let target {
            store.repair(target, url: url)
        } else {
            store.add(url)
        }
    }
}

#if DEBUG
#Preview("File destinations, empty") {
    LauncherFileDestinationsSettingsCard(
        store: LauncherFileDestinationsStore(defaults: UserDefaults(suiteName: "FileDestinationsPreview")!)
    )
    .padding().frame(width: 640)
}
#endif

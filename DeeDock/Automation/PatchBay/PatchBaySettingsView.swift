import SwiftUI

/// The current mode's connected display ports, plus every saved cable for removal and status.
struct PatchBaySettingsView: View {
    let controller: PatchBayController
    let profiles: DisplayProfilesStore
    @State private var selectedDisplayID = ""
    @State private var confirmsReset = false

    private var displays: [DisplaySnapshot] {
        profiles.displays.filter { $0.hostsDock && profiles.document.profiles[$0.id]?.enabled == true }
    }
    private var displayID: String {
        displays.contains { $0.id == selectedDisplayID } ? selectedDisplayID : (displays.first?.id ?? "")
    }
    private var pins: [DockPin] { profiles.pinLists[displayID] ?? [] }
    private var modeID: UUID { profiles.modes.activeMode.id }
    private var cables: [PatchBayCable] {
        controller.document.cables.filter { $0.displayID == displayID && $0.modeID == modeID }
    }

    var body: some View {
        SettingsCard(title: .patchBayTitle, footnote: .patchBayHelp) {
            SettingsToggleRow(title: .patchBayEnabled,
                              isOn: Binding(get: { controller.document.enabled }, set: { controller.setEnabled($0) }))
                .disabled(controller.requiresReset)
            VStack(alignment: .leading, spacing: 12) {
                Picker(selection: Binding(get: { displayID }, set: { selectedDisplayID = $0 })) {
                    ForEach(displays) { display in Text(verbatim: display.name).tag(display.id) }
                } label: { Text(.patchBayDisplay) }
                .disabled(displays.isEmpty)
                Text(.patchBayMode(name: profiles.modes.activeMode.name))
                    .font(.caption).foregroundStyle(.secondary)
                if pins.contains(where: { $0.application != nil }), pins.contains(where: { $0.folder != nil }) {
                    PatchBayBoard(apps: pins.filter { $0.application != nil },
                                  folders: pins.filter { $0.folder != nil }, cables: cables) { appID, folderID in
                        controller.connect(appID: appID, folderID: folderID, displayID: displayID)
                    }
                    .id(displayID + modeID.uuidString)
                    .disabled(controller.requiresReset || profiles.requiresReset || profiles.modes.requiresReset
                              || profiles.pinErrors[displayID] != nil)
                } else {
                    ContentUnavailableView {
                        Label(.patchBayEmptyTitle, systemImage: "point.3.connected.trianglepath.dotted")
                    } description: { Text(.patchBayEmptyHelp) }
                }
            }
            .padding(SettingsMetrics.rowInset)
        }
        SettingsCard(title: .patchBaySavedCables, footnote: .patchBayLimitsHelp) {
            if controller.document.cables.isEmpty {
                Text(.patchBayNoCables).foregroundStyle(.secondary).padding(SettingsMetrics.rowInset)
            }
            ForEach(controller.document.cables) { cable in
                PatchBayCableRow(cable: cable, controller: controller, profiles: profiles)
            }
            if let message = controller.message {
                Text(message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsMetrics.rowInset)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if controller.runningCableID != nil {
                Button(.patchBayStop) { controller.stop() }.padding(SettingsMetrics.rowInset)
            }
            if controller.requiresReset {
                Button(.patchBayReset, role: .destructive) { confirmsReset = true }
                    .padding(SettingsMetrics.rowInset)
            }
        }
        .confirmationDialog(Text(.patchBayReset), isPresented: $confirmsReset) {
            Button(.patchBayReset, role: .destructive) { controller.reset() }
        } message: { Text(.patchBayResetHelp) }
    }
}

/// Textual routing and action buttons remain usable with VoiceOver and without seeing the wires.
private struct PatchBayCableRow: View {
    let cable: PatchBayCable
    let controller: PatchBayController
    let profiles: DisplayProfilesStore

    private var modeName: String {
        profiles.modes.modes.first { $0.id == cable.modeID }?.name ?? String(localized: .patchBayMissingMode)
    }
    private var displayName: String {
        profiles.document.profiles[cable.displayID]?.name ?? String(localized: .patchBayMissingDisplay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.patchBayConnection(appName: cable.appName, folderName: cable.folderName))
                .fontWeight(.medium)
            Text(.patchBayScope(display: displayName, mode: modeName))
                .font(.caption).foregroundStyle(.secondary)
            if !controller.isAvailable(cable) {
                Label(.patchBayUnavailable, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(.patchBayRun) { controller.run(cable) }
                    .disabled(!controller.document.enabled || controller.requiresReset
                              || !controller.isAvailable(cable) || controller.runningCableID != nil)
                Button(.patchBayDisconnect, role: .destructive) { controller.disconnect(cable.id) }
                    .disabled(controller.requiresReset)
            }
            if controller.lastCableID == cable.id, let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SettingsMetrics.rowInset)
        .accessibilityElement(children: .contain)
    }
}

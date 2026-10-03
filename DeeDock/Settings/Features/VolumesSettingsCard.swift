import SwiftUI

/// External drives, disk images, and network shares in the dock, plus the hard-disk eject question.
/// Every option below the first depends on the drives switch and dims with it.
struct VolumesSettingsCard: View {
    let source: SettingsValueSource

    var body: some View {
        let showsVolumes = source.binding(\.showVolumes)
        SettingsCard(title: .settingsVolumes, footnote: .settingsVolumesHelp) {
            SettingsToggleRow(title: .settingsShowVolumes, isOn: showsVolumes)
            SettingsToggleRow(title: .settingsShowDiskImages, isOn: source.binding(\.showDiskImages),
                              disabled: !showsVolumes.wrappedValue)
            SettingsToggleRow(title: .settingsShowNetworkVolumes, isOn: source.binding(\.showNetworkVolumes),
                              disabled: !showsVolumes.wrappedValue)
            SettingsToggleRow(title: .settingsConfirmBeforeEjectingDisks,
                              subtitle: .settingsConfirmBeforeEjectingDisksHelp,
                              isOn: source.binding(\.confirmBeforeEjectingDisks),
                              disabled: !showsVolumes.wrappedValue)
        }
    }
}

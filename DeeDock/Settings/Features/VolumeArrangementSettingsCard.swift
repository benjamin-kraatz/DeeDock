import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The drives DOKK remembers, in dock order. Dragging a row reorders the dock live, the eye hides
/// or shows a drive, and disconnected drives can be forgotten.
///
/// Edits go to the same arrangement as the dock's context menu and tile drags, so both stay in step.
struct VolumeArrangementSettingsCard: View {
    let store: VolumeArrangementStore
    /// Mounted volumes, for their real icons and to tell connected drives from remembered ones.
    let mounted: [VolumeDockItem]
    /// Kinds the dock includes. Rows for other kinds stay hidden, since they never reach the dock.
    let visibility: VolumeVisibility
    @State private var draggedID: String?

    private var rows: [VolumeArrangementEntry] {
        let kinds = VolumeVisibility(showsVolumes: true, showsDiskImages: visibility.showsDiskImages,
                                     showsNetworkVolumes: visibility.showsNetworkVolumes,
                                     showsTimeMachineVolumes: visibility.showsTimeMachineVolumes)
        return store.entries.filter { kinds.includes($0.kind) }
    }

    var body: some View {
        let rows = rows
        let ids = rows.map(\.id)
        let icons = Dictionary(mounted.map { ($0.volumeID, $0.icon) }, uniquingKeysWith: { first, _ in first })
        SettingsCard(title: .settingsDriveList, footnote: .settingsDriveListHelp) {
            if rows.isEmpty {
                SettingsStatusRow(symbol: "externaldrive.badge.plus", tint: .secondary,
                                  message: Text(.settingsDriveListEmpty))
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                    VolumeArrangementRow(
                        entry: entry, icon: icons[entry.volumeID],
                        canMoveUp: index > 0, canMoveDown: index < rows.count - 1,
                        setHidden: { hidden in
                            withAnimation(.snappy(duration: 0.25)) { store.setHidden(entry.volumeID, hidden) }
                        },
                        move: { distance in
                            withAnimation(.snappy(duration: 0.25)) {
                                store.move(entry.volumeID, to: index + distance, within: ids)
                            }
                        },
                        forget: {
                            withAnimation(.snappy(duration: 0.25)) { store.forget(entry.volumeID) }
                        }
                    )
                    .onDrag {
                        draggedID = entry.id
                        return NSItemProvider(object: entry.id as NSString)
                    } preview: {
                        VolumeArrangementDragPreview(entry: entry, icon: icons[entry.volumeID])
                    }
                    .onDrop(of: [.text], delegate: VolumeRowDropDelegate(target: entry.id, sequence: ids,
                                                                         store: store, draggedID: $draggedID))
                }
            }
        }
        // A drop between rows misses every row's delegate; it still ends the drag here.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            draggedID = nil
            return false
        }
    }
}

/// Live reordering: entering another row moves the dragged drive into its place at once, so the
/// list and every dock show the new order before release.
private struct VolumeRowDropDelegate: DropDelegate {
    let target: String
    /// The listed drive IDs in order, including the dragged one.
    let sequence: [String]
    let store: VolumeArrangementStore
    @Binding var draggedID: String?

    func validateDrop(info: DropInfo) -> Bool { draggedID != nil }

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != target, let index = sequence.firstIndex(of: target) else { return }
        withAnimation(.snappy(duration: 0.25)) { store.move(draggedID, to: index, within: sequence) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

/// The floating row under the pointer while a drive is dragged.
private struct VolumeArrangementDragPreview: View {
    let entry: VolumeArrangementEntry
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 9) {
            VolumeArrangementIcon(icon: icon, kind: entry.kind)
            Text(verbatim: entry.name).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: .rect(cornerRadius: 9, style: .continuous))
    }
}

#if DEBUG
private enum VolumeArrangementPreviewData {
    static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    static func store(empty: Bool = false) -> VolumeArrangementStore {
        let entries: [VolumeArrangementEntry] = empty ? [] : [
            VolumeArrangementEntry(volumeID: "stick", name: "USB-Stick", kind: .removable, isHidden: false, lastSeen: now),
            VolumeArrangementEntry(volumeID: "backup", name: "Time Machine Backup", kind: .externalDisk, isHidden: true,
                                   lastSeen: now),
            VolumeArrangementEntry(volumeID: "card", name: "EOS_DIGITAL", kind: .removable, isHidden: false,
                                   lastSeen: now.addingTimeInterval(-3 * 86_400)),
            VolumeArrangementEntry(volumeID: "image", name: "Xcode Installer", kind: .diskImage, isHidden: true,
                                   lastSeen: now.addingTimeInterval(-40 * 86_400)),
        ]
        return VolumeArrangementStore(previewing: VolumeArrangement(entries: entries))
    }

    static var mounted: [VolumeDockItem] {
        let icon = NSWorkspace.shared.icon(for: .volume)
        return [("stick", "USB-Stick", VolumeKind.removable), ("backup", "Time Machine Backup", .externalDisk)].map {
            VolumeDockItem(info: VolumeInfo(volumeID: $0.0, url: URL(fileURLWithPath: "/Volumes/\($0.1)"), name: $0.1,
                                            kind: $0.2), icon: icon, isEjecting: false)
        }
    }

    static let visibility = VolumeVisibility(showsVolumes: true, showsDiskImages: true, showsNetworkVolumes: false)
}

#Preview("Drives list") {
    VolumeArrangementSettingsCard(store: VolumeArrangementPreviewData.store(), mounted: VolumeArrangementPreviewData.mounted,
                                  visibility: VolumeArrangementPreviewData.visibility)
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Drives list, dark") {
    VolumeArrangementSettingsCard(store: VolumeArrangementPreviewData.store(), mounted: VolumeArrangementPreviewData.mounted,
                                  visibility: VolumeArrangementPreviewData.visibility)
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}

#Preview("Drives list, empty") {
    VolumeArrangementSettingsCard(store: VolumeArrangementPreviewData.store(empty: true), mounted: [],
                                  visibility: VolumeArrangementPreviewData.visibility)
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif

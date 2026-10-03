import SwiftUI
import UniformTypeIdentifiers

/// A mounted volume next to Trash. Click shows its contents as a stack; hover shows the volume
/// card; dragging it off the dock ejects it.
struct DockVolumeButton: View {
    let item: VolumeDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openVolume?(item) } label: {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction.layout.edge,
                available: !item.isEjecting, running: false, launching: false,
                keyboardSelected: selected, artworkOpacity: artworkOpacity,
                artworkAnimation: interaction.idleFade.animation)
                .overlay {
                    if interaction.volumeTargetID == item.id {
                        DockDocumentHighlight(emphasized: interaction.springEmphasized).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    DockVolumeBadge(kind: item.kind, ejecting: item.isEjecting, size: size)
                        .offset(x: -2, y: -DockGeometry.indicatorAreaDepth - 2)
                        .animation(interaction.idleFade.animation) { $0.opacity(artworkOpacity) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item.isEjecting)
        .overlay {
            if !item.isEjecting, let begin = interaction.beginVolumeDrag {
                DockVolumeDragSourceView(item: item, primaryAction: { interaction.openVolume?(item) }, begin: begin,
                                         tracking: { interaction.sourceTrackingChanged?($0) })
            }
        }
        .overlay {
            VolumeContextMenuBridge(item: item, interaction: interaction, openSettings: {
                interaction.prepareVolumeSettings?()
                openWindow.openDockSettings()
            }, tracking: menuTracking)
        }
        .opacity(interaction.dragSourceID == item.id ? 0.3 : 1)
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(.volumeDockHint))
        .accessibilityActions {
            Button(.volumeOpen) { interaction.openVolume?(item) }
            Button(.volumeOpenInFinder) { interaction.revealVolume?(item) }
            Button(.volumeEject) { interaction.ejectVolume?(item) }
            Button(.volumeHideFromDock) { interaction.hideVolume?(item) }
            if interaction.canMoveVolume?(item.volumeID, -1) == true {
                Button { interaction.moveVolume?(item.volumeID, -1) } label: {
                    Text(interaction.layout.edge.isVertical ? .actionMoveUp : .actionMoveLeft)
                }
            }
            if interaction.canMoveVolume?(item.volumeID, 1) == true {
                Button { interaction.moveVolume?(item.volumeID, 1) } label: {
                    Text(interaction.layout.edge.isVertical ? .actionMoveDown : .actionMoveRight)
                }
            }
        }
    }

    private var accessibilityValue: LocalizedStringResource {
        if item.isEjecting { return .volumeEjecting }
        let kind = item.kind.title
        guard let total = item.info.totalCapacity, let available = item.info.availableCapacity else { return kind }
        return .volumeAccessibilityValue(kind: String(localized: kind),
                                         capacity: String(localized: .volumeCapacitySummary(
                                             total: VolumeCapacityFormat.string(total),
                                             available: VolumeCapacityFormat.string(available))))
    }
}

/// The corner badge that makes a volume read as a drive at dock size. While ejecting it turns into
/// a spinner, so the dimmed tile visibly has work in progress.
struct DockVolumeBadge: View {
    let kind: VolumeKind
    let ejecting: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if ejecting {
                ProgressView().controlSize(.mini).tint(.white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: kind.badgeSymbol)
                    .font(.system(size: max(9, size * 0.2), weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: max(14, size * 0.3), height: max(14, size * 0.3))
        .background(ejecting ? AnyShapeStyle(.gray) : AnyShapeStyle(.tint), in: Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
        .animation(.spring(duration: 0.3), value: ejecting)
        .accessibilityHidden(true)
    }
}

extension VolumeKind {
    /// Spoken and shown name of the kind, for VoiceOver values and Settings.
    var title: LocalizedStringResource {
        switch self {
        case .removable: .volumeKindRemovable
        case .externalDisk: .volumeKindExternalDisk
        case .diskImage: .volumeKindDiskImage
        case .network: .volumeKindNetwork
        }
    }
}

#if DEBUG
#Preview("Volume tiles") {
    let interaction = DockInteraction()
    let icon = NSWorkspace.shared.icon(for: .volume)
    let tiles: [VolumeDockItem] = [
        VolumeDockItem(info: VolumeInfo(volumeID: "stick", url: URL(fileURLWithPath: "/Volumes/USB-Stick"), name: "USB-Stick",
                                        kind: .removable, totalCapacity: 128_000_000_000, availableCapacity: 42_000_000_000),
                       icon: icon, isEjecting: false),
        VolumeDockItem(info: VolumeInfo(volumeID: "disk", url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup",
                                        kind: .externalDisk, totalCapacity: nil, availableCapacity: nil),
                       icon: icon, isEjecting: false),
        VolumeDockItem(info: VolumeInfo(volumeID: "image", url: URL(fileURLWithPath: "/Volumes/Installer"), name: "Installer",
                                        kind: .diskImage, totalCapacity: nil, availableCapacity: nil),
                       icon: icon, isEjecting: true),
    ]
    return HStack(spacing: 12) {
        ForEach(tiles) { tile in
            DockVolumeButton(item: tile, size: 64, selected: false, interaction: interaction,
                             menuTracking: { _ in }, accessibilityFocus: { _ in })
        }
    }
    .padding(24)
}
#endif

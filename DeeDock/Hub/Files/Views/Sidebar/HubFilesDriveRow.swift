import SwiftUI

/// A mounted volume: name, free space underneath, and an eject button that spins while ejecting.
struct HubFilesDriveRow: View {
    let model: HubFilesModel
    let volume: HubVolumes.Volume
    /// The sidebar's namespace for the sliding current-location fill.
    let currentFill: Namespace.ID

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    private var location: HubFilesLocation { .folder(normalizing: volume.url) }
    private var isEjecting: Bool { model.volumes.ejecting.contains(volume.url) }
    private var isCurrent: Bool { !model.isSearching && model.isCurrent(location) }
    private var isDropTarget: Bool { model.dropHighlight == .sidebar(HubFilesPath.normalized(volume.url)) }

    private var freeText: String? {
        volume.availableBytes.map { String(localized: .hubFilesDriveFree(HubFilesFormatting.size($0))) }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 19, height: 19)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: volume.name)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                if let freeText {
                    Text(verbatim: freeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if volume.isEjectable { Color.clear.frame(width: 22, height: 22) }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: HubFilesMetrics.rowHeight)
        .padding(.vertical, freeText == nil ? 0 : 2)
        .modifier(HubFilesSidebarItemBackground(isCurrent: isCurrent, isHovered: hovered, isDropTarget: isDropTarget,
                                                currentFill: currentFill))
        .opacity(isEjecting ? 0.5 : 1)
        .overlay {
            HubFilesInteractionRegion(
                interaction: HubFilesInteractions.sidebar(location, model: model) { hovered = $0 },
                model: model)
        }
        .overlay(alignment: .trailing) {
            if volume.isEjectable {
                HubFilesEjectButton(isEjecting: isEjecting) { model.eject(volume) }
                    .padding(.trailing, 10)
            }
        }
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.2)), value: isEjecting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: volume.name))
        .accessibilityValue(Text(verbatim: freeText ?? ""))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.show(location) }
        .accessibilityAction(named: Text(.hubFilesEject)) { if volume.isEjectable { model.eject(volume) } }
    }
}

/// The eject control. Spins while the unmount is in flight.
private struct HubFilesEjectButton: View {
    let isEjecting: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isEjecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "eject.fill").font(.system(size: 10))
                }
            }
            .foregroundStyle(hovered ? .primary : .secondary)
            .frame(width: 22, height: 22)
            .background(hovered && !isEjecting ? HubFilesTheme(scheme).chipHighlight : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isEjecting)
        .onHover { hovered = $0 }
        .help(Text(.hubFilesEject))
        .accessibilityLabel(Text(.hubFilesEject))
    }
}

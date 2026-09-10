import SwiftUI

/// One shortcut tile with native icon framing and execution feedback shared across displays.
///
/// The tile has two appearances. By default it is the purple bolt Action Tile. When the optional
/// Shortcut greenhouse is on it draws ``ShortcutGreenhouseArtwork`` instead, and a pin whose
/// shortcut has disappeared wilts and dims like an unavailable app. Both appearances click through
/// to the same runner: ``ActionTilesController/water(_:)`` is an alias of `run`, so no second
/// execution path exists. File drops keep landing on the drop target that owns this button.
struct DockActionButton: View {
    let item: ActionDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var accessibilityFocused: Bool

    /// Plant chrome only when the shared store exists and the user opted in.
    private var greenhouse: Bool { interaction.greenhouse?.isEnabled == true }
    /// A wilted plant is only meaningful while the greenhouse is on.
    private var wilted: Bool { greenhouse && item.wilted }

    var body: some View {
        Button {
            if greenhouse {
                interaction.actionTiles?.water(item.tile.id)
            } else {
                interaction.actionTiles?.run(item.tile.id)
            }
        } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: !wilted, running: false, launching: false,
                                 keyboardSelected: selected,
                                 artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                                    idleFraction: interaction.idleFade.fraction,
                                    reduceTransparency: reduceTransparency).icons,
                                 artworkAnimation: interaction.idleFade.animation) {
                artwork
                    .overlay(alignment: .bottomTrailing) {
                        statusBadge.padding(2).background(.regularMaterial, in: .circle)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(item.status.busy)
        .help(helpText)
        .accessibilityLabel(Text(verbatim: item.tile.name))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Text(hint))
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
    }

    @ViewBuilder private var artwork: some View {
        if greenhouse {
            ShortcutGreenhouseArtwork(health: item.plant.health, status: item.status,
                                      size: size, reduceMotion: reduceMotion)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23).fill(.purple.gradient)
                Image(systemName: "bolt.fill").font(.system(size: size * 0.48)).foregroundStyle(.white)
            }
        }
    }

    private var hint: LocalizedStringResource {
        greenhouse ? .greenhouseWaterHint : .actionsTileHint
    }

    /// Tooltips concatenate independently translated fragments the way the other dock tiles do.
    private var helpText: String {
        guard greenhouse else { return item.tile.name + " · " + item.status.title }
        let health: LocalizedStringResource = wilted ? .greenhouseWilted : .greenhouseHealthy
        let action: LocalizedStringResource = wilted ? .greenhouseWiltedHelp : .greenhouseWater
        return item.tile.name + " · " + String(localized: health) + " · "
            + item.status.title + " · " + String(localized: action)
    }

    /// The status title comes from Shortcuts or from a run error, so it is never a localization key.
    private var accessibilityValue: Text {
        guard greenhouse else { return Text(verbatim: item.status.title) }
        let value: LocalizedStringResource = wilted
            ? .greenhouseWiltedValue(item.status.title)
            : .greenhouseHealthyValue(item.status.title)
        return Text(value)
    }

    @ViewBuilder private var statusBadge: some View {
        switch item.status {
        case .idle: EmptyView()
        case .running:
            if interaction.exposesContent { ProgressView().controlSize(.mini) }
            else { Image(systemName: "hourglass") }
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }
}

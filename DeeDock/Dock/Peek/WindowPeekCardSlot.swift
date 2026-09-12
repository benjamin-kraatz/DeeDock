import SwiftUI

/// One card plus the affordances that belong to it, so the card owns its own hover state.
///
/// The Add to Fusion control is revealed by the pointer being anywhere on the card, not only on the
/// control itself, which is what makes hiding it at rest acceptable.
struct WindowPeekCardSlot: View {
    let card: WindowPeekCard
    let appIcon: NSImage
    let settings: DockSettings
    let selected: Bool
    let size: CGSize
    let manage: () -> Void
    let choose: () -> Void
    let watch: () -> Void
    let addToFusion: () -> Void
    let pinPortal: () -> Void
    @State private var hovering = false

    var body: some View {
        WindowPeekCardView(card: card, appIcon: appIcon, settings: settings,
                           selected: selected, action: choose)
            .contextMenu {
                Button(.peekActionTitle, systemImage: "ellipsis", action: manage)
                Divider()
                Button(.watchTitle, systemImage: "eye", action: watch)
                Button(.portalPin, systemImage: "pin", action: pinPortal)
                Button(.fusionAdd, systemImage: "plus.square.on.square", action: addToFusion)
            }
            .accessibilityAction(named: Text(.peekActionTitle), manage)
            .accessibilityAction(named: Text(.watchTitle), watch)
            .accessibilityAction(named: Text(.fusionAdd), addToFusion)
            .accessibilityAction(named: Text(.portalPin), pinPortal)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    WindowPeekActionButton(revealed: hovering || selected, label: .peekActionTitle,
                                           symbol: "ellipsis", action: manage)
                    WindowPeekActionButton(revealed: hovering || selected, label: .watchTitle,
                                           symbol: "eye", action: watch)
                    WindowPeekActionButton(revealed: hovering || selected, label: .fusionAdd,
                                           symbol: "plus.square.on.square", action: addToFusion)
                }
                .padding(7)
            }
            .frame(width: size.width, height: size.height)
            .onHover { hovering = $0 }
    }
}

/// Presents explicit window actions on the card that is already showing the source.
///
/// A bordered button sat as a grey slab on top of every thumbnail; this is a round glass control
/// that stays out of the picture until the pointer is on the card. Keyboard selection reveals it
/// too, and the card's context menu and accessibility action reach the same place.
private struct WindowPeekActionButton: View {
    let revealed: Bool
    let label: LocalizedStringResource
    let symbol: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed ? 1 : 0.9)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: revealed)
        // Hidden means gone: an invisible target must not swallow clicks meant for the card.
        .allowsHitTesting(revealed)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}


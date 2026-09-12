import SwiftUI

/// Two captured windows from the current app, using the same actions as ordinary Peek cards.
struct WindowPeekSplitView: View {
    let state: WindowPeekState

    private var settings: DockSettings { WindowPeekGeometry.splitSettings(state.settings) }
    private var paneHeight: CGFloat { WindowPeekGeometry.cardSize(settings).height }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(.windowPeekSplitTitle, systemImage: "rectangle.split.2x1")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(.windowPeekSplitShowAll) { state.showsAllWindows = true }
                    .font(.caption)
            }
            GeometryReader { geometry in
                HStack(spacing: 13) {
                    ForEach(state.splitCards) { card in
                        WindowPeekCardSlot(
                            card: card, appIcon: state.appIcon, settings: settings,
                            selected: state.selectedID == card.id,
                            size: CGSize(width: max(1, (geometry.size.width - 13) / 2), height: paneHeight),
                            manage: { state.manage?(card.id) }, choose: { state.choose?(card.id) },
                            watch: { state.watch?(card.id) },
                            addToFusion: { state.addToFusion?(card.window) },
                            pinPortal: { state.pinPortal?(card.window) }
                        )
                        .overlay(alignment: .leading) {
                            if card.id != state.splitCards.first?.id { Divider().offset(x: -7) }
                        }
                    }
                }
            }
            .frame(height: paneHeight)
            if state.cards.count > 2 {
                HStack {
                    Button(.windowPeekSplitPrevious, systemImage: "chevron.backward") { state.select(by: -1) }
                    Spacer(minLength: 8)
                    Button(.windowPeekSplitNext, systemImage: "chevron.forward") { state.select(by: 1) }
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.windowPeekSplitTitle))
    }
}

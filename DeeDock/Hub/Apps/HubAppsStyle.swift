import AppKit
import SwiftUI

/// Apps-tab metrics and fills from the approved mockup (`docs/mockups/dokk-hub.html`, `.apps`,
/// `.agrid`, `.sc`). Shared Hub values come from ``HubStyle``.
enum HubAppsStyle {
    /// Content insets inside the tab (mockup `.apps` padding: 16 26 24).
    static let contentInsets = EdgeInsets(top: 16, leading: 26, bottom: 24, trailing: 26)
    /// Smallest grid tile width; columns grow to fill the row.
    static let tileMinWidth: CGFloat = 104
    static let gridColumnSpacing: CGFloat = 6
    static let gridRowSpacing: CGFloat = 8
    static let tileIconSize: CGFloat = 56
    static let tileCornerRadius: CGFloat = 14
    static let listIconSize: CGFloat = 32
    static let suggestionIconSize: CGFloat = 44
    static let suggestionSpacing: CGFloat = 12
    static let tileHoverScale: CGFloat = 1.06
    /// Entrance: tiles rise 10 pt from 96 % scale, 14 ms apart (capped at 16 tiles); cards 40 ms apart.
    static var entrance: Animation { .spring(response: 0.45, dampingFraction: 0.78) }
    static let entranceOffset: CGFloat = 10
    static let entranceScale: CGFloat = 0.96
    static let tileStagger: Double = 0.014
    static let cardStagger: Double = 0.04
    /// Tiles created later than this after the tab appeared skip the entrance, so scrolling a lazy
    /// grid never animates cells in.
    static let entranceWindow: TimeInterval = 0.6

    /// Grid columns for a content width, using the same arithmetic as CSS
    /// `repeat(auto-fill, minmax(104px, 1fr))` with a 6 pt gap. Keyboard navigation uses this
    /// count, so it must match the rendered grid.
    static func columns(forContentWidth width: CGFloat) -> Int {
        max(1, Int((width + gridColumnSpacing) / (tileMinWidth + gridColumnSpacing)))
    }

    /// Hover wash (mockup `--chip`).
    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.07) : .black.opacity(0.05)
    }

    /// Active chip and pressed wash (mockup `--chipHi`).
    static func chipHighlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.12) : .black.opacity(0.09)
    }

    /// Resting card fill (mockup `--card2`).
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.045) : .white.opacity(0.5)
    }

    /// Hairline around cards (mockup `--line`).
    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.075)
    }
}

/// The mockup's staggered entrance (`.stag`): fade, rise, and scale in after a per-index delay.
///
/// Decided once when the view is created: only views created right after the tab appeared animate,
/// and Reduce Motion shows them in place. The initial state is set in `init` so a non-animated
/// view never renders one invisible frame.
struct HubAppsEntrance: ViewModifier {
    private let delay: Double
    @State private var shown: Bool

    init(index: Int, stagger: Double = HubAppsStyle.tileStagger, appearedAt: Date) {
        delay = Double(min(index, 16)) * stagger
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && Date().timeIntervalSince(appearedAt) < HubAppsStyle.entranceWindow
        _shown = State(initialValue: !animates)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : HubAppsStyle.entranceOffset)
            .scaleEffect(shown ? 1 : HubAppsStyle.entranceScale)
            .onAppear {
                guard !shown else { return }
                withAnimation(HubAppsStyle.entrance.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Applies ``HubAppsEntrance``.
    func hubAppsEntrance(index: Int, stagger: Double = HubAppsStyle.tileStagger, appearedAt: Date) -> some View {
        modifier(HubAppsEntrance(index: index, stagger: stagger, appearedAt: appearedAt))
    }
}

/// The mockup's section title row (`.sect`): a 13 pt semibold secondary title with optional
/// trailing controls.
struct HubAppsSectionHeader<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            title
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(EdgeInsets(top: 6, leading: 4, bottom: 12, trailing: 4))
    }
}

extension HubAppsSectionHeader where Trailing == EmptyView {
    init(title: Text) {
        self.init(title: title) { EmptyView() }
    }
}

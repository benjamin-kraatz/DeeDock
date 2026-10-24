import SwiftUI

/// Metrics shared by the sheet's rows (mockup `.row`): 8 pt side padding so rows line up with the section
/// headings, at least 42 pt tall, and a soft wash while the pointer is over a row the user can still change.
///
/// The wash fades in 0.15 s; under Reduce Motion it switches without animation.
struct HubUninstallRowChrome: ViewModifier {
    /// Whether the row reacts to the pointer. Off while removal runs, where nothing can be changed.
    let hoverable: Bool

    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: HubStyle.rowRadius, style: .continuous)
                    .fill(HubAppsStyle.card(colorScheme))
                    .opacity(hovered && hoverable ? 1 : 0)
            }
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}

extension View {
    /// Lays the view out as one of the uninstall sheet's rows. See ``HubUninstallRowChrome``.
    func hubUninstallRow(hoverable: Bool) -> some View {
        modifier(HubUninstallRowChrome(hoverable: hoverable))
    }

    /// Section-heading type and spacing (mockup `.sec`: 11.5 pt semibold, secondary, 14 pt above, 4 below,
    /// 8 pt to the sides so the heading lines up with the rows).
    func hubUninstallSectionHeading() -> some View {
        font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(EdgeInsets(top: 14, leading: 8, bottom: 4, trailing: 8))
    }
}

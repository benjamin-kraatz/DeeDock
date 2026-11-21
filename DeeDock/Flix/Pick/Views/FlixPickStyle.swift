import SwiftUI

/// Flix Pick's measurements and colours, from the approved mockup (`docs/mockups/flix-pick.html`,
/// style Tuck). Metrics are in points; the panel's outer sizes are in ``FlixPickPlacement``.
///
/// The icon column is what the closed rail shows, so everything in it shares one centre line:
/// `listInset + rowPadding + iconBox / 2` is half of ``FlixPickPlacement/railWidth``, and the
/// header's logo sits in a box of the same place and width.
enum FlixPickStyle {
    // MARK: Metrics
    static let cornerRadius: CGFloat = 14
    /// The far shadow under the rail: shorter than the Flix panel's, as the rail is slim.
    static let shadow = FlixPanelGlass.Shadow(radius: 17, y: 8)
    /// Space between the body's edge and a row.
    static let listInset: CGFloat = 6
    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 1
    static let rowPadding: CGFloat = 8
    /// The square a row's icon is centred in; the icon itself is ``iconSize``.
    static let iconBox: CGFloat = 30
    static let iconSize: CGFloat = 28
    static let iconGap: CGFloat = 10
    static let logoSize: CGFloat = 20

    /// A row's width in the open rail and in the closed one.
    static let rowWidth = FlixPickPlacement.openWidth - listInset * 2
    static let railRowWidth = FlixPickPlacement.railWidth - listInset * 2
    /// The icon column's centre from the body's leading edge.
    static let iconCenter = listInset + rowPadding + iconBox / 2

    // MARK: Text
    /// The emphasised words of a footer hint: the mockup's second text level, between primary and
    /// ``FlixStyle/faint``. A fixed opacity, so it reads the same on glass and on the solid body.
    static let emphasis = Color.primary.opacity(0.65)

    // MARK: Reasons

    /// The reason line's colour: context purple, used before the accent colour, new orange,
    /// learned green.
    ///
    /// The mockup's own values: the system colours in dark appearance, and darker ones in light
    /// appearance, where the system's orange and green are too pale for 11-point text on glass.
    static func tint(_ tone: FlixPickReason.Tone, dark: Bool) -> Color {
        switch tone {
        case .context: dark ? Color(red: 0.749, green: 0.353, blue: 0.949) : Color(red: 0.647, green: 0.314, blue: 0.847)
        case .used: .accentColor
        case .new: warning(dark: dark)
        case .learned: dark ? Color(red: 0.188, green: 0.82, blue: 0.345) : Color(red: 0.157, green: 0.655, blue: 0.271)
        }
    }

    /// Orange for "new" and for the footer's note when an action could not reach the picker.
    static func warning(dark: Bool) -> Color {
        dark ? Color(red: 1, green: 0.624, blue: 0.039) : Color(red: 0.878, green: 0.525, blue: 0)
    }
}

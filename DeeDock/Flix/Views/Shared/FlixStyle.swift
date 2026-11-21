import SwiftUI

/// Flix Files' measurements and colours, from the approved mockup (`docs/mockups/flix-files-ai.html`).
///
/// Colours are semantic (they follow light and dark appearance and the accent colour) except the
/// intelligence gradient, which is the mockup's own. Metrics are in points.
enum FlixStyle {
    // MARK: Metrics
    static let cornerRadius: CGFloat = 16
    static let sidebarWidth: CGFloat = 184
    static let headerHeight: CGFloat = 46
    static let footerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 50
    static let childRowHeight: CGFloat = 44
    static let rowRadius: CGFloat = 9
    static let iconSize: CGFloat = 36
    /// Header buttons, sidebar rows, the search field, card buttons.
    static let controlRadius: CGFloat = 7
    static let cardRadius: CGFloat = 12
    /// Sheets and the drop question.
    static let surfaceRadius: CGFloat = 14
    /// Fact, meaning, and conversion chips.
    static let chipRadius: CGFloat = 5

    // MARK: Intelligence
    static let aiViolet = Color(red: 0.545, green: 0.424, blue: 1)
    static let aiBlue = Color(red: 0.227, green: 0.659, blue: 1)
    static let aiPink = Color(red: 1, green: 0.435, blue: 0.694)
    /// The ✦ gradient: violet, blue at 55 %, pink.
    static let aiGradient = LinearGradient(stops: [.init(color: aiViolet, location: 0),
                                                   .init(color: aiBlue, location: 0.55),
                                                   .init(color: aiPink, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
    /// The two-stop gradient behind primary ✦ buttons and the tile pill.
    static let aiButtonGradient = LinearGradient(colors: [aiViolet, aiBlue], startPoint: .leading, endPoint: .trailing)
    /// The faint diagonal wash behind ✦ cards.
    static let aiWash = LinearGradient(colors: [aiViolet.opacity(0.12), aiBlue.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let aiSoft = Color(red: 0.588, green: 0.431, blue: 1).opacity(0.16)
    static let aiStroke = aiViolet.opacity(0.35)

    // MARK: Surfaces and lines
    static let chip = Color.primary.opacity(0.07)
    static let chipHover = Color.primary.opacity(0.12)
    static let hover = Color.primary.opacity(0.06)
    static let pane = Color.primary.opacity(0.035)
    static let field = Color.primary.opacity(0.06)
    static let key = Color.primary.opacity(0.09)
    /// Hairlines between the panel's regions.
    static let line = Color.primary.opacity(0.08)
    /// Outlines of fields, cards, and floating surfaces.
    static let outline = Color.primary.opacity(0.15)
    static let accentSoft = Color.accentColor.opacity(0.2)
    /// The opaque colour of sheets, the drop question, and the toast.
    static let surface = Color(nsColor: .windowBackgroundColor)

    // MARK: Text
    /// The mockup's third text level (counts, hints, section titles). Stronger than the system's
    /// tertiary label, which is too faint at 10–11 points on glass.
    static let faint = Color.primary.opacity(0.42)
}

/// A half-point line between the panel's regions, stronger with Increase Contrast.
struct FlixHairline: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(contrast == .increased ? Color.primary.opacity(0.4) : FlixStyle.line)
            .frame(width: axis == .vertical ? 0.5 : nil, height: axis == .horizontal ? 0.5 : nil)
            .accessibilityHidden(true)
    }
}

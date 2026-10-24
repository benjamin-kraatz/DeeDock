import AppKit

/// Which suggested questions fit on one row of pills, measured with the font `RobiPillStyle`
/// draws them in.
///
/// The built-in actions use `ViewThatFits` instead. Questions are measured because the ones that
/// do not fit move into the More menu on the row above, and that row has to know which they are.
enum RobiPillFit {
    /// A pill's horizontal padding, its symbol, and the gap between symbol and title, plus a few
    /// points of slack so a rounding difference never pushes the last pill past the row's edge.
    static let chrome: CGFloat = 46
    static let spacing: CGFloat = 6

    static func width(of title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width) + chrome
    }

    /// Splits `titles` into those shown on a row `available` points wide, in order, and the
    /// rest. A title that does not fit is skipped, so a shorter one after it can still take the
    /// space.
    static func split(_ titles: [String], available: CGFloat) -> (shown: [String], overflow: [String]) {
        var used: CGFloat = 0
        var shown: [String] = []
        var overflow: [String] = []
        for title in titles {
            let next = width(of: title) + (shown.isEmpty ? 0 : spacing)
            if used + next <= available {
                shown.append(title)
                used += next
            } else {
                overflow.append(title)
            }
        }
        return (shown, overflow)
    }
}

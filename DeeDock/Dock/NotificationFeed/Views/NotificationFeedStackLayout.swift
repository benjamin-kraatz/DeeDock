import SwiftUI

/// Lays out one sender's rows, either folded into a stack or unfolded into a list.
///
/// Folded: the newest row in front at full width, each card behind it 4 pt lower and 8 pt
/// narrower on each side, at the front card's height, so only their bottom edges peek out. At
/// most three cards show; the rest sit behind the last one. Unfolded: rows one below the other,
/// 6 pt apart. Because both arrangements place the same subviews, toggling `isExpanded` inside
/// an animation slides rows out from under the front card and back.
///
/// Subviews are expected newest first, with `zIndex` falling with their position so the front
/// card draws on top.
struct NotificationFeedStackLayout: Layout {
    var isExpanded: Bool
    var spacing: CGFloat = 6

    /// How much lower each card behind the front sits.
    static let peekStep: CGFloat = 4
    /// How much narrower each card behind the front is, on each side.
    static let peekInset: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let first = subviews.first else { return .zero }
        let width = proposal.width ?? first.sizeThatFits(.unspecified).width
        if isExpanded {
            let heights = subviews.map { height(of: $0, width: width) }
            return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(subviews.count - 1))
        }
        let peeks = min(subviews.count, NotificationFeedGrouping.maximumStackDepth) - 1
        return CGSize(width: width, height: height(of: first, width: width) + Self.peekStep * CGFloat(peeks))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        if isExpanded {
            var y = bounds.minY
            for subview in subviews {
                let height = height(of: subview, width: bounds.width)
                subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            }
            return
        }
        let frontHeight = height(of: first, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let depth = CGFloat(min(index, NotificationFeedGrouping.maximumStackDepth - 1))
            let inset = Self.peekInset * depth
            subview.place(at: CGPoint(x: bounds.minX + inset, y: bounds.minY + Self.peekStep * depth),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: max(0, bounds.width - inset * 2), height: frontHeight))
        }
    }

    private func height(of subview: LayoutSubview, width: CGFloat) -> CGFloat {
        subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }
}

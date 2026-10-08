import SwiftUI

/// The notice row in Window Peek: who wrote, how much is new, and up to two lines of the message.
///
/// Drawn the same in the panel and in flight, so the swap when the flight lands cannot be seen.
/// The red tint and dot repeat the badge ring; banner text is OS-supplied and shown verbatim.
struct WindowPeekNoticeStrip: View {
    let notice: WindowPeekNotice
    @Environment(\.colorScheme) private var colorScheme

    static let cornerRadius: CGFloat = 10

    private var red: Color { Color(nsColor: .systemRed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(red).frame(width: 7, height: 7)
                Text(verbatim: notice.sender)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: notice.summary)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(red)
                    .fixedSize()
            }
            if let message = notice.message {
                Text(verbatim: message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    // Aligns with the sender, past the dot.
                    .padding(.leading, 13)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(red.opacity(colorScheme == .dark ? 0.13 : 0.08), in: .rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(red.opacity(colorScheme == .dark ? 0.38 : 0.3), lineWidth: 0.5)
        }
    }
}

/// Shows `fraction` of its content's natural height and clips the rest.
///
/// The content keeps its full size and is pinned to the edge nearest the dock, so while Peek grows
/// the strip appears to slide out of the panel's edge, and its frame already sits where it will rest.
/// The flight aims at that frame from the first tick.
struct WindowPeekNoticeReveal: Layout {
    var fraction: CGFloat
    /// True on bottom, left, and right docks, where the strip sits below the windows.
    var pinsBottom: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: natural.height * min(max(fraction, 0), 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let natural = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let y = pinsBottom ? bounds.maxY - natural.height : bounds.minY
        content.place(at: CGPoint(x: bounds.minX, y: y),
                      proposal: ProposedViewSize(width: bounds.width, height: natural.height))
    }
}

#if DEBUG
private let previewNotice = WindowPeekNotice(summary: "1 new", sender: "Mike Hoffmann",
    message: "Good Morning, Mr Dikkmann. Are we still on for 10 tomorrow? I can bring the drafts.")

#Preview("Notice strip") {
    VStack(spacing: 12) {
        WindowPeekNoticeStrip(notice: previewNotice)
        WindowPeekNoticeStrip(notice: WindowPeekNotice(summary: "New", sender: "Calendar", message: nil))
    }
    .frame(width: 264)
    .padding(16)
    .background(.regularMaterial)
}

#Preview("Notice strip, German, light") {
    WindowPeekNoticeStrip(notice: WindowPeekNotice(summary: "3 neu", sender: "Familie Hoffmann-Dikkmann",
        message: "Treffen wir uns morgen um zehn? Ich bringe die Entwürfe mit."))
        .frame(width: 228)
        .padding(16)
        .background(.regularMaterial)
        .preferredColorScheme(.light)
}

#Preview("Half revealed") {
    WindowPeekNoticeReveal(fraction: 0.5, pinsBottom: true) {
        WindowPeekNoticeStrip(notice: previewNotice).padding(.top, 10)
    }
    .clipped()
    .frame(width: 264)
    .padding(16)
    .background(.regularMaterial)
}
#endif

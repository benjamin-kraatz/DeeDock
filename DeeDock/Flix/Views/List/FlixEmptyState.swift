import SwiftUI

/// Nothing to show, said plainly with a quiet symbol: an empty history, a filter with nothing in
/// it, a search without results, or nothing similar.
struct FlixEmptyState: View {
    enum Kind {
        /// Nothing has been tracked yet.
        case noHistory
        /// The sidebar filter matches nothing.
        case emptyFilter
        /// The search matches nothing.
        case noResults
        /// More like this found nothing.
        case nothingSimilar

        var symbol: String {
            switch self {
            case .noHistory: "tray"
            case .emptyFilter: "line.3.horizontal.decrease.circle"
            case .noResults: "magnifyingglass"
            case .nothingSimilar: "square.stack.3d.up.slash"
            }
        }
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: kind.symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(FlixStyle.faint)
                .frame(height: 34)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(kind == .noHistory ? .flixEmptyTitle : .flixNothingMatchesTitle)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(kind == .noHistory ? .flixEmptyMessage : .flixNothingMatchesMessage)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Empty states") {
    HStack(alignment: .top, spacing: 0) {
        FlixEmptyState(kind: .noHistory)
        FlixEmptyState(kind: .emptyFilter)
        FlixEmptyState(kind: .noResults)
    }
    .frame(width: 760)
}

#Preview("Empty history, German") {
    FlixEmptyState(kind: .noHistory)
        .frame(width: 400)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif

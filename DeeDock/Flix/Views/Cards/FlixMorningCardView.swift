import SwiftUI

/// "☀︎ Where were you?": yesterday's threads on the first open of a day.
struct FlixMorningCardView: View {
    let card: FlixMorningCard
    let run: (FlixMorningCard.Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        FlixCard(intelligent: true) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(.flixMorningTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Text((try? AttributedString(markdown: card.message)) ?? AttributedString(card.message))
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 6) {
                // Wraps when the actions do not fit beside each other.
                FlixFlow {
                    ForEach(card.actions) { action in
                        FlixCardButton(title: action.label, primary: action.isPrimary) { run(action) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FlixCloseButton(action: dismiss)
                    .padding(.top, 2)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Morning card") {
    FlixMorningCardView(card: FlixPreviewData.morning, run: { _ in }, dismiss: {})
        .padding().frame(width: 500)
}

#Preview("Morning card, narrow, light") {
    FlixMorningCardView(card: FlixMorningCard(
        message: "Gestern ging es um **Berlin-Fotos** und den **Oak-&-Ash-Vertrag**.",
        actions: [.init(label: "Oak & Ash wieder öffnen", target: .open([]), isPrimary: true),
                  .init(label: "Berlin-Fotos", target: .filter(.all)),
                  .init(label: "Monatliche Rechnungen", target: .filter(.all))]), run: { _ in }, dismiss: {})
        .padding().frame(width: 340)
        .preferredColorScheme(.light)
}
#endif

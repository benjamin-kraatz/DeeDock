import SwiftUI

/// "☀︎ Where were you?": yesterday's threads on the first open of a day.
struct FlixMorningCardView: View {
    let card: FlixMorningCard
    let run: (FlixMorningCard.Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        FlixCard(intelligent: true) {
            Label { Text(.flixMorningTitle) } icon: { Image(systemName: "sun.max") }
                .font(.system(size: 14, weight: .semibold))
            Text((try? AttributedString(markdown: card.message)) ?? AttributedString(card.message))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(card.actions) { action in
                    FlixCardButton(title: action.label, primary: action.isPrimary) { run(action) }
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.flixDismiss))
            }
        }
    }
}

#if DEBUG
#Preview("Morning card") {
    FlixMorningCardView(card: FlixMorningCard(
        message: "Yesterday you were on **Berlin trip photos** and the **Oak & Ash contract**.",
        actions: [.init(label: "Reopen Oak & Ash", target: .open([]), isPrimary: true),
                  .init(label: "Berlin photos", target: .filter(.all))]), run: { _ in }, dismiss: {})
        .padding().frame(width: 500)
}
#endif

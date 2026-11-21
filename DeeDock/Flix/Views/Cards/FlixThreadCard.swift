import SwiftUI

/// A Thread's card at the top of its list: name, summary, Open All, Ask Robi. Dragging the card
/// carries every item in the Thread.
struct FlixThreadCard: View {
    let thread: FlixThread
    let count: Int
    let state: FlixPanelState

    private var members: [FlixItem] { thread.memberIDs.compactMap(state.history.item) }

    var body: some View {
        FlixCard(intelligent: true) {
            HStack(spacing: 8) {
                Text(verbatim: thread.emoji).font(.system(size: 15))
                Text(verbatim: thread.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if thread.namedByAppleIntelligence {
                    FlixNamedChip()
                }
            }
            .allowsHitTesting(false)
            if let summary = thread.summary {
                Text(verbatim: summary)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 6) {
                FlixCardButton(title: String(localized: .flixThreadOpenAll(count)), primary: true) {
                    state.openThread(thread)
                }
                if state.intelligence.canAskRobi {
                    FlixCardButton(title: String(localized: .flixMenuAskRobi)) { state.askRobi(members, origin: .threadCard) }
                }
                // The hint gives way first: it shrinks a little, then truncates.
                Text(.flixThreadDragHint)
                    .font(.system(size: 11))
                    .foregroundStyle(FlixStyle.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
            .padding(.top, 2)
        }
        .background {
            FlixRowInteraction(press: { _, _ in }, click: { _, _ in }, open: { state.openThread(thread) },
                               begin: { view, event in state.beginDrag?(members.map(\.id), view, event, .threadCard) },
                               menu: { nil })
                .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: thread.name))
        .accessibilityHint(Text(.flixThreadDragHint))
    }
}

/// "✦ named by Apple Intelligence".
private struct FlixNamedChip: View {
    var body: some View {
        Text(verbatim: "✦ " + String(localized: .flixThreadNamedByAppleIntelligence))
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .foregroundStyle(.secondary)
            .background(FlixStyle.chip, in: RoundedRectangle(cornerRadius: FlixStyle.chipRadius, style: .continuous))
            .fixedSize()
            .accessibilityLabel(Text(.flixThreadNamedByAppleIntelligence))
    }
}

#if DEBUG
#Preview("Thread card") {
    let state = FlixPreviewData.panelState(.thread)
    return FlixThreadCard(thread: FlixPreviewData.threads[0], count: 4, state: state)
        .padding().frame(width: 500)
}

#Preview("Thread card, German, long name") {
    let state = FlixPreviewData.panelState(.thread)
    let thread = FlixThread(id: "long", name: "Verpackungskonzept Oak & Ash für das Frühjahr 2027", emoji: "🌳",
                            summary: "Vertrag heute unterschrieben. Das Angebot ist bereit zur Durchsicht.",
                            memberIDs: FlixPreviewData.threads[0].memberIDs, namedByAppleIntelligence: true)
    return FlixThreadCard(thread: thread, count: 4, state: state)
        .padding().frame(width: 500)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif

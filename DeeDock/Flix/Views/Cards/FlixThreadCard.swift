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
                Text(verbatim: thread.emoji)
                Text(verbatim: thread.name).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 6)
                if thread.namedByAppleIntelligence {
                    FlixFactChip(fact: FlixFact(text: "✦ " + String(localized: .flixThreadNamedByAppleIntelligence)))
                }
            }
            .allowsHitTesting(false)
            if let summary = thread.summary {
                Text(verbatim: summary)
                    .font(.system(size: 12))
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
                Text(.flixThreadDragHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
        }
        .background {
            FlixRowInteraction(press: { _, _ in }, click: { _, _ in }, open: { state.openThread(thread) },
                               begin: { view, event in state.beginDrag?(members.map(\.id), view, event, .threadCard) },
                               menu: { nil })
                .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: thread.name))
    }
}

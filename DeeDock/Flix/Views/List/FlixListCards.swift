import SwiftUI

/// The cards above the rows, each only while its slot has content: the search head while
/// searching, the More like this bar, a Thread's card, and on the plain list the folder access
/// card, the morning card, Save this page, and the Fits card. Each fades up as it arrives.
struct FlixListCards: View {
    let state: FlixPanelState
    /// Top-level rows in the list, for the Thread card's "Open All".
    let count: Int

    private var rise: AnyTransition { FlixMotion.rise(reduceMotion: state.reduceMotion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.searchActive {
                FlixSearchHead(state: state)
            }
            if let like = state.intelligence.moreLikeThis, let source = state.history.item(like.sourceID) {
                FlixMoreLikeThisBar(name: source.name, count: like.resultIDs?.count, loading: like.resultIDs == nil,
                                    reduceMotion: state.reduceMotion, clear: state.intelligence.clearMoreLikeThis)
                    .transition(rise)
            }
            if case .thread(let id) = state.filter, !state.searchActive, let thread = state.intelligence.thread(id) {
                FlixThreadCard(thread: thread, count: count, state: state)
                    .transition(rise)
            }
            if state.isPlainList {
                if !state.foldersAwaitingAccess.isEmpty, !state.accessCardDismissed {
                    FlixFolderAccessCard(folders: state.foldersAwaitingAccess,
                                         allow: { state.requestFolderAccess?($0) },
                                         dismiss: { state.accessCardDismissed = true })
                        .transition(rise)
                }
                if let morning = state.intelligence.morning {
                    FlixMorningCardView(card: morning, run: { state.runMorningAction($0, card: morning) },
                                        dismiss: { state.dismissMorning(morning) })
                        .onAppear { state.metrics?.morningShown() }
                        .transition(rise)
                }
                if let offer = state.pageOffer {
                    FlixSavePageCard(offer: offer, reduceMotion: state.reduceMotion, save: { state.savePage?() })
                        .transition(rise)
                }
                FlixFitsSection(state: state)
            }
        }
    }
}

import SwiftUI

/// Column view: one 200 pt column per folder from the nearest sidebar location to the current
/// folder, scrolled so the last column is visible.
struct HubFilesColumnsView: View {
    let context: HubFilesPaneContext

    private var pane: HubFilesPane { context.pane }

    var body: some View {
        let chain = pane.pathChain
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    if pane.location == .recents {
                        HubFilesColumn(context: context, folder: nil, items: pane.items, pathChild: nil)
                    } else {
                        ForEach(Array(chain.enumerated()), id: \.element) { offset, folder in
                            HubFilesColumn(context: context, folder: folder, items: pane.columnListing(for: folder),
                                           pathChild: offset + 1 < chain.count ? chain[offset + 1] : nil)
                                .id(folder)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
                .animation(HubFilesMotion.animation(.easeOut(duration: 0.22)), value: chain)
            }
            .scrollIndicators(.automatic)
            .overlay { HubFilesPaneStatusOverlay(pane: pane).allowsHitTesting(false) }
            .onChange(of: chain, initial: true) { _, chain in
                guard let last = chain.last else { return }
                withAnimation(HubFilesMotion.layout) { proxy.scrollTo(last, anchor: .trailing) }
            }
        }
    }
}

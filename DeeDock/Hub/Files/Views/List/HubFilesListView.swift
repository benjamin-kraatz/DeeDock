import SwiftUI

/// List view: a sortable header and 32 pt rows. Empty space below the rows is the pane's own
/// drop target and clears the selection on click.
struct HubFilesListView: View {
    let context: HubFilesPaneContext

    var body: some View {
        VStack(spacing: 0) {
            HubFilesListHeader(pane: context.pane, showsKind: context.showsKind)
            HubFilesPaneScroll(context: context) {
                LazyVStack(spacing: 0) {
                    ForEach(context.pane.items) { item in
                        HubFilesListRow(context: context, item: item)
                            .id(item.url)
                            .transition(.asymmetric(insertion: .opacity,
                                                    removal: .opacity.combined(with: .offset(x: 14)).combined(with: .scale(scale: 0.97))))
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10))
                .animation(HubFilesMotion.animation(.easeOut(duration: 0.26)), value: context.pane.items.map(\.url))
            }
        }
    }
}

/// The pane's scrolling body: fills the viewport so empty space accepts clicks and drops, shows
/// loading, empty, and error states, and scrolls to keyboard selections.
struct HubFilesPaneScroll<Content: View>: View {
    let context: HubFilesPaneContext
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                        .background {
                            HubFilesInteractionRegion(
                                interaction: HubFilesInteractions.paneBackground(context.pane, paneIndex: context.index,
                                                                                 model: context.model),
                                model: context.model)
                        }
                }
                .overlay { HubFilesPaneStatusOverlay(pane: context.pane).allowsHitTesting(false) }
                .onChange(of: context.pane.scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(HubFilesMotion.quick) { proxy.scrollTo(request.url) }
                }
            }
        }
    }
}

/// Loading, empty, and unreadable-folder states over a pane's body.
struct HubFilesPaneStatusOverlay: View {
    let pane: HubFilesPane

    var body: some View {
        Group {
            switch pane.loadState {
            case .loading where pane.items.isEmpty:
                ProgressView().controlSize(.small)
            case .failed(let message):
                VStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 22, weight: .light))
                    Text(.hubFilesUnreadableFolder)
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: message)
                        .font(.system(size: 11.5))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.tertiary)
                .padding(24)
            case .loaded where pane.items.isEmpty:
                Text(pane.location == .recents ? .hubFilesNoRecents : .hubFilesEmptyFolder)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

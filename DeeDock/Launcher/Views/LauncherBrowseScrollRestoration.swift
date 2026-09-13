import SwiftUI

/// Seeds each new results view from the retained offset. Context identity recreates it at the top
/// when filtering, sorting, grouping, grid width, or the ordered app results change.
struct LauncherBrowseScrollRestoration: ViewModifier {
    let state: LauncherState
    let context: LauncherBrowseScroll.Context
    @State private var position: ScrollPosition

    init(state: LauncherState, context: LauncherBrowseScroll.Context) {
        self.state = state
        self.context = context
        let saved = state.browseScroll
        // This is the new scroll view's initial command; subsequent user scrolling owns position.
        let offset = saved.flatMap { $0.context == context ? $0.offset : nil } ?? 0
        _position = State(initialValue: ScrollPosition(y: offset))
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear {
                if state.browseScroll?.context != context {
                    state.browseScroll = LauncherBrowseScroll(context: context, offset: 0)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, min(geometry.contentOffset.y,
                           geometry.contentSize.height - geometry.containerSize.height))
            } action: { _, offset in
                // Closing tears down suggestions and layout. Those geometry changes must not
                // overwrite the position the user last saw before dismissal.
                guard state.contentVisible, !state.usesMixedResults, !state.usesFileActions else { return }
                state.browseScroll = LauncherBrowseScroll(context: context, offset: offset)
            }
    }
}

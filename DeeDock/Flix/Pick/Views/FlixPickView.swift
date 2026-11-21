import SwiftUI

/// Flix Pick's panel, style Tuck (`docs/mockups/flix-pick.html`): a rail of file icons beside
/// another app's picker that springs open on hover to show names, reasons, places, and times.
///
/// The content is always laid out at the open width and clipped to the body's current width, so
/// opening only reveals it and nothing reflows. The body sits against the window edge next to the
/// picker (`FlixPickPanelController` keeps that edge still). It arrives with a short slide from the
/// picker and a fade, and leaves the same way (``FlixPickEntrance``); with Reduce Motion it only
/// fades. Reduce Transparency draws a solid body (``FlixPanelGlass``).
struct FlixPickView: View {
    let state: FlixPickState

    var body: some View {
        let width = state.isOpen ? FlixPickPlacement.openWidth : FlixPickPlacement.railWidth
        let height = FlixPickPlacement.height(rows: state.rows.count, open: state.isOpen)
        FlixPickContent(state: state)
            .frame(width: FlixPickPlacement.openWidth, alignment: .topLeading)
            .frame(width: width, height: height, alignment: .topLeading)
            .modifier(FlixPanelGlass(reduceTransparency: state.reduceTransparency,
                                     increaseContrast: state.increaseContrast,
                                     radius: FlixPickStyle.cornerRadius, shadow: FlixPickStyle.shadow))
            .background { FlixPickHoverTracker { state.hoverChanged?($0) } }
            .modifier(FlixPickEntrance(shown: state.isShown, side: state.side, reduceMotion: state.reduceMotion))
            .padding(FlixPickPlacement.shadowMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: state.side == .right ? .topLeading : .topTrailing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.flixPickName))
    }
}

/// Header, rows, and footer at the open width.
private struct FlixPickContent: View {
    let state: FlixPickState

    var body: some View {
        VStack(spacing: 0) {
            FlixPickHeader(state: state)
            VStack(spacing: FlixPickStyle.rowSpacing) {
                if state.rows.isEmpty {
                    FlixPickEmptyRow(state: state)
                } else {
                    ForEach(state.rows) { row in
                        FlixPickRowView(row: row, state: state)
                    }
                }
            }
            .padding(.horizontal, FlixPickStyle.listInset)
            .padding(.top, 2)
            .padding(.bottom, FlixPickPlacement.listPadding - 2)
            FlixPickFooter(state: state)
        }
    }
}

#if DEBUG
#Preview("Flix Pick, closed rail") {
    FlixPickView(state: FlixPickPreviewData.state(open: false))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 440)
}

#Preview("Flix Pick, open") {
    FlixPickView(state: FlixPickPreviewData.state(open: true))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 440)
}

#Preview("Flix Pick, open, light") {
    FlixPickView(state: FlixPickPreviewData.state(open: true))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 440)
        .preferredColorScheme(.light)
}

#Preview("Flix Pick, Save picker, German") {
    FlixPickView(state: FlixPickPreviewData.state(kind: .save, open: true))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 320)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Flix Pick, nothing fits") {
    FlixPickView(state: FlixPickPreviewData.state(open: true, rows: 0))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 200)
}

#Preview("Flix Pick, a row at work, the picker did not respond") {
    let state = FlixPickPreviewData.state(open: true, rows: 4)
    state.busyRowID = state.rows[1].id
    state.draggingRowID = state.rows[3].id
    state.message = String(localized: .flixPickFailed)
    return FlixPickView(state: state)
        .frame(width: FlixPickPlacement.openWidth + 60, height: 380)
}

#Preview("Flix Pick, Reduce Transparency") {
    let state = FlixPickPreviewData.state(open: true, rows: 3)
    state.reduceTransparency = true
    return FlixPickView(state: state)
        .frame(width: FlixPickPlacement.openWidth + 60, height: 320)
}

#Preview("Flix Pick, left of the picker, closed, light") {
    let state = FlixPickPreviewData.state(open: false, rows: 3)
    state.side = .left
    return FlixPickView(state: state)
        .frame(width: FlixPickPlacement.openWidth + 60, height: 320)
        .preferredColorScheme(.light)
}
#endif

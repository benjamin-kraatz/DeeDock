import SwiftUI

/// Flix Pick's panel, style Tuck (`docs/mockups/flix-pick.html`): a rail of file icons beside
/// another app's picker that springs open on hover to show names, reasons, places, and times.
///
/// The content is always laid out at the open width and clipped to the body's current width, so
/// opening only reveals it and nothing reflows. The body sits against the window edge next to the
/// picker (`FlixPickPanelController` keeps that edge still). It arrives with a short slide from the
/// picker and a fade; with Reduce Motion it only fades. Reduce Transparency draws a solid body
/// (`FlixPanelGlass`).
struct FlixPickView: View {
    let state: FlixPickState

    var body: some View {
        let width = state.isOpen ? FlixPickPlacement.openWidth : FlixPickPlacement.railWidth
        let height = FlixPickPlacement.height(rows: state.rows.count, open: state.isOpen)
        let slide: CGFloat = state.side == .right ? -12 : 12
        FlixPickContent(state: state)
            .frame(width: FlixPickPlacement.openWidth, alignment: .topLeading)
            .frame(width: width, height: height, alignment: .topLeading)
            .modifier(FlixPanelGlass(reduceTransparency: state.reduceTransparency,
                                     increaseContrast: state.increaseContrast))
            .background { FlixPickHoverTracker { state.hoverChanged?($0) } }
            .opacity(state.isShown ? 1 : 0)
            .offset(x: state.isShown || state.reduceMotion ? 0 : slide)
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
            VStack(spacing: 1) {
                if state.rows.isEmpty {
                    FlixPickEmptyRow(state: state)
                } else {
                    ForEach(state.rows) { row in
                        FlixPickRowView(row: row, state: state)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, FlixPickPlacement.listPadding - 2)
            FlixPickFooter(state: state)
        }
    }
}

#if DEBUG
/// Deterministic sample rows for the previews: paths in protected folders, so no thumbnail is read.
@MainActor
enum FlixPickPreviewData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func state(kind: FlixPickPickerKind = .open, open: Bool, rows: Int = 5) -> FlixPickState {
        let state = FlixPickState()
        state.kind = kind
        state.appName = "Pages"
        state.buttonTitle = kind == .open ? "Open" : "Save"
        state.rows = Array((kind == .open ? files : folders).prefix(rows))
        state.isOpen = open
        state.isShown = true
        state.now = now
        return state
    }

    private static func row(_ path: String, kind: FlixItemKind, reason: String, tone: FlixPickReason.Tone,
                            location: String, minutes: Double) -> FlixPickRow {
        let date = now.addingTimeInterval(-minutes * 60)
        let item = FlixItem(path: path, name: (path as NSString).lastPathComponent, kind: kind, activity: .opened,
                            date: date, contentTypeIdentifier: kind == .folder ? nil : "com.apple.iwork.pages.sffpages")
        return FlixPickRow(item: item, reason: FlixPickReason(text: reason, tone: tone), location: location, date: date)
    }

    static let files: [FlixPickRow] = [
        row("/Users/mia/Documents/Oak & Ash/Brief v3.pages", kind: .document, reason: "Part of Oak & Ash",
            tone: .context, location: "Documents › Oak & Ash", minutes: 20),
        row("/Users/mia/Documents/Newsletter November.pages", kind: .document, reason: "Picked here 3×",
            tone: .learned, location: "Documents", minutes: 1_440),
        row("/Users/mia/Desktop/Certificate – Mia.pages", kind: .document, reason: "New in Desktop",
            tone: .new, location: "Desktop", minutes: 42),
        row("/Users/mia/Desktop/Client Letters/Quarterly Letter.pages", kind: .document, reason: "Edited recently",
            tone: .used, location: "Desktop › Client Letters", minutes: 180),
        row("/Users/mia/Documents/Offer – Oak & Ash.pages", kind: .document, reason: "You send documents here",
            tone: .used, location: "Documents", minutes: 5_760),
    ]

    static let folders: [FlixPickRow] = [
        row("/Users/mia/Desktop/Client Letters", kind: .folder, reason: "Saved here 3×", tone: .learned,
            location: "Desktop", minutes: 180),
        row("/Users/mia/Documents/Oak & Ash", kind: .folder, reason: "Where your recent Pages files are",
            tone: .used, location: "Documents", minutes: 20),
        row("/Users/mia/Documents/Invoices", kind: .folder, reason: "You saved files here recently", tone: .used,
            location: "Documents", minutes: 2_880),
    ]
}

#Preview("Flix Pick, closed rail") {
    FlixPickView(state: FlixPickPreviewData.state(open: false))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 440)
}

#Preview("Flix Pick, open") {
    FlixPickView(state: FlixPickPreviewData.state(open: true))
        .frame(width: FlixPickPlacement.openWidth + 60, height: 440)
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

#Preview("Flix Pick, Reduce Transparency") {
    let state = FlixPickPreviewData.state(open: true, rows: 3)
    state.reduceTransparency = true
    return FlixPickView(state: state)
        .frame(width: FlixPickPlacement.openWidth + 60, height: 320)
}

#Preview("Flix Pick, left of the picker, light") {
    let state = FlixPickPreviewData.state(open: true, rows: 3)
    state.side = .left
    return FlixPickView(state: state)
        .frame(width: FlixPickPlacement.openWidth + 60, height: 320)
        .preferredColorScheme(.light)
}
#endif

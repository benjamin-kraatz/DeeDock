import SwiftUI

/// One Flix Pick row: the real file icon, the name, the coloured reason, where it is, and when.
///
/// In the closed rail only the icon shows; the text fades in as the rail opens. Hover only
/// highlights. A click selects in the picker, ⌥-click and double-click also press its default
/// button, and a drag drops the file in (``FlixPickRowInteraction``). A click flashes the row for
/// a moment (``FlixPickMotion/hit``), it stays tinted while its action runs, and it dims while it
/// is dragged. For VoiceOver the row is one button with its name, reason, and place, and two
/// actions: select (or go there) and open (or save here).
struct FlixPickRowView: View {
    let row: FlixPickRow
    let state: FlixPickState

    @State private var hovered = false
    @State private var pressed = false
    /// The pressed look kept for a moment after a click; `hits` counts the clicks that start it.
    @State private var flashing = false
    @State private var hits = 0
    @Environment(\.colorScheme) private var colorScheme

    private var busy: Bool { state.busyRowID == row.id }
    private var dragged: Bool { state.draggingRowID == row.id }
    private var isSave: Bool { state.kind == .save }
    /// Held down, or just clicked.
    private var down: Bool { pressed || flashing }
    /// The icon while the rail is closed, so a press never nudges the icon column.
    private var pressAnchor: UnitPoint {
        state.isOpen ? .center : UnitPoint(x: FlixPickStyle.iconCenter / FlixPickStyle.rowWidth, y: 0.5)
    }

    var body: some View {
        HStack(spacing: FlixPickStyle.iconGap) {
            FlixThumbnailView(item: row.item, size: FlixPickStyle.iconSize, policy: state.policy)
                .frame(width: FlixPickStyle.iconBox, height: FlixPickStyle.iconBox)
                .allowsHitTesting(false)
            FlixPickRowText(row: row, tint: FlixPickStyle.tint(row.reason.tone, dark: colorScheme == .dark))
                .flixPickReveal(state.isOpen)
            Text(FlixRelativeTime.string(for: row.date, now: state.now))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(FlixStyle.faint)
                .fixedSize()
                .flixPickReveal(state.isOpen)
        }
        .padding(.horizontal, FlixPickStyle.rowPadding)
        .frame(height: FlixPickStyle.rowHeight)
        .background(alignment: .leading) {
            FlixPickRowHighlight(level: busy || down ? .active : hovered ? .hover : .none, open: state.isOpen)
        }
        .scaleEffect(down && !state.reduceMotion ? FlixPickMotion.pressScale : 1, anchor: pressAnchor)
        .opacity(dragged ? 0.35 : 1)
        .animation(FlixMotion.hover, value: down)
        .animation(FlixMotion.hover, value: dragged)
        .background {
            FlixPickRowInteraction(press: { pressed = $0 },
                                   click: { option in
                                       flash()
                                       state.activate?(row, option ? .optionClick : .click, option)
                                   },
                                   doubleClick: {
                                       flash()
                                       state.activate?(row, .doubleClick, true)
                                   },
                                   begin: { view, event in state.beginDrag?(row, view, event) },
                                   hover: { hovered = $0 })
        }
        // Ends the flash. Owned by the row: a newer click restarts the wait, and a row that goes
        // away cancels it.
        .task(id: hits) {
            guard hits > 0 else { return }
            try? await Task.sleep(for: FlixPickMotion.hit)
            guard !Task.isCancelled else { return }
            flashing = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.item.name))
        .accessibilityValue(Text(verbatim: row.reason.text + ", " + row.location))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { state.activate?(row, .accessibility, false) }
        .accessibilityAction(named: Text(isSave ? .flixPickActionGoThere : .flixPickActionSelect)) {
            state.activate?(row, .accessibility, false)
        }
        .accessibilityAction(named: Text(isSave ? .flixPickActionSaveHere : .flixPickActionOpen)) {
            state.activate?(row, .accessibility, true)
        }
    }

    /// Starts the pressed look at once, before the mouse-up clears `pressed`, so the two join
    /// without a gap.
    private func flash() {
        flashing = true
        hits += 1
    }
}

/// A row's three lines: the name, why it is suggested in the reason's colour, and where it is.
private struct FlixPickRowText: View {
    let row: FlixPickRow
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: row.item.name)
                .font(.system(size: 12.5))
                .truncationMode(.middle)
            Text(verbatim: row.reason.text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            // From the head, so the folder the file is in always shows.
            Text(verbatim: row.location)
                .font(.system(size: 10.5))
                .foregroundStyle(FlixStyle.faint)
                .truncationMode(.head)
                .padding(.top, 1)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The rounded fill behind a row: quiet on hover, accent-tinted while pressed or busy.
///
/// It is as wide as the rail shows: a square around the icon while the rail is closed, the whole
/// row when it is open. The width rides the rail's spring, so the fill's trailing edge stays the
/// same distance inside the body's while it opens; only the colour takes the quick hover fade.
private struct FlixPickRowHighlight: View {
    nonisolated enum Level { case none, hover, active }

    let level: Level
    let open: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: FlixStyle.rowRadius, style: .continuous)
            .fill(color)
            .animation(FlixMotion.hover, value: level)
            .frame(width: open ? FlixPickStyle.rowWidth : FlixPickStyle.railRowWidth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch level {
        case .none: .clear
        case .hover: FlixStyle.hover
        case .active: FlixStyle.accentSoft
        }
    }
}

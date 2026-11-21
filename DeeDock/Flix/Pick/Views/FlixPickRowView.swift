import SwiftUI

/// One Flix Pick row: the real file icon, the name, the coloured reason, where it is, and when.
///
/// In the closed rail only the icon shows; the text fades in as the rail opens. Hover only
/// highlights. A click selects in the picker, ⌥-click and double-click also press its default
/// button, and a drag drops the file in (``FlixPickRowInteraction``). For VoiceOver the row is one
/// button with its name, reason, and place, and two actions: select (or go there) and open (or
/// save here).
struct FlixPickRowView: View {
    let row: FlixPickRow
    let state: FlixPickState

    @State private var hovered = false
    @State private var pressed = false

    private var busy: Bool { state.busyRowID == row.id }
    private var isSave: Bool { state.kind == .save }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.rowRadius, style: .continuous)
        HStack(spacing: 10) {
            FlixThumbnailView(item: row.item, size: 28, policy: state.policy)
                .frame(width: 30, height: 30)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.item.name)
                    .font(.system(size: 12.5))
                    .truncationMode(.middle)
                Text(verbatim: row.reason.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlixPickRowView.tint(row.reason.tone))
                Text(verbatim: row.location)
                    .font(.system(size: 10.5))
                    .foregroundStyle(FlixStyle.faint)
                    .truncationMode(.head)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flixPickReveal(state.isOpen)
            Text(FlixRelativeTime.string(for: row.date, now: state.now))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(FlixStyle.faint)
                .fixedSize()
                .flixPickReveal(state.isOpen)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background {
            shape.fill(busy || pressed ? FlixStyle.accentSoft : hovered ? FlixStyle.hover : .clear)
                .allowsHitTesting(false)
        }
        .scaleEffect(pressed && !state.reduceMotion ? 0.985 : 1)
        .animation(FlixMotion.hover, value: pressed)
        .animation(FlixMotion.hover, value: busy)
        .background {
            FlixPickRowInteraction(press: { pressed = $0 },
                                   click: { option in state.activate?(row, option ? .optionClick : .click, option) },
                                   doubleClick: { state.activate?(row, .doubleClick, true) },
                                   begin: { view, event in state.beginDrag?(row, view, event) },
                                   hover: { hovered = $0 })
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

    /// The reason line's colour: context purple, used before the accent colour, new orange,
    /// learned green, as in the mockup.
    static func tint(_ tone: FlixPickReason.Tone) -> Color {
        switch tone {
        case .context: .purple
        case .used: .accentColor
        case .new: .orange
        case .learned: .green
        }
    }
}

/// Fades text in as the rail opens (shortly after its width starts to grow) and out at once as it
/// closes. Only opacity changes, so it is the same with Reduce Motion.
struct FlixPickTextReveal: ViewModifier {
    let open: Bool

    func body(content: Content) -> some View {
        content
            .opacity(open ? 1 : 0)
            .animation(open ? .easeOut(duration: 0.2).delay(0.08) : .easeOut(duration: 0.12), value: open)
    }
}

extension View {
    /// Applies ``FlixPickTextReveal``.
    func flixPickReveal(_ open: Bool) -> some View { modifier(FlixPickTextReveal(open: open)) }
}

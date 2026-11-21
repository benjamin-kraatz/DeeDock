import SwiftUI

/// Shows the current sheet over the list: Tidy and New Smart Filter drop from the top, Ask Robi
/// rises from the bottom, Rename sits at the top. A click on the dimmed list closes it.
///
/// A sheet arrives with ``FlixMotion/sheet`` from ten points away at 97 %, and leaves faster,
/// easing in. With Reduce Motion it crossfades.
struct FlixSheetLayer: View {
    let state: FlixPanelState

    var body: some View {
        ZStack(alignment: alignment) {
            if state.sheet != nil {
                Color.black.opacity(0.14)
                    .contentShape(.rect)
                    .onTapGesture { state.sheet = nil }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            if let sheet = state.sheet {
                FlixSheetChrome {
                    switch sheet {
                    case .tidy: FlixTidySheet(state: state)
                    case .smartFilter: FlixSmartFilterSheet(state: state)
                    case .askRobi(let ids): FlixAskRobiSheet(state: state, items: ids.compactMap(state.history.item))
                    case .rename(let id):
                        if let item = state.history.item(id) { FlixRenameSheet(state: state, item: item) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(alignment == .top ? .top : .bottom, alignment == .top ? 52 : 36)
                .transition(transition)
                .id(sheet.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(animation, value: state.sheet)
    }

    private var alignment: Alignment {
        if case .askRobi = state.sheet { return .bottom }
        return .top
    }

    /// The opening spring; closing eases in over 150 ms, as the mockup does.
    private var animation: Animation {
        if state.reduceMotion { return FlixMotion.fade }
        return state.sheet == nil ? .easeIn(duration: 0.15) : FlixMotion.sheet
    }

    private var transition: AnyTransition {
        if state.reduceMotion { return .opacity }
        let top = alignment == .top
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: top ? -10 : 10)).combined(with: .scale(scale: 0.97)),
            removal: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98)))
    }
}

/// The sheet's surface: opaque, rounded, shadowed. Its content settles with a spring when it
/// grows (an answer arriving, a rule added).
struct FlixSheetChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FlixFloatingSurface())
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

/// A sheet's title row: an optional mark, the title, a quiet trailing note, and the close button.
struct FlixSheetTitle: View {
    /// What leads the title.
    enum Mark { case none, sparkle, robi }

    let title: Text
    var mark: Mark = .none
    var trailing: Text?
    let close: () -> Void

    /// A title with the ✦ mark when `intelligent`.
    init(title: Text, intelligent: Bool = false, trailing: Text? = nil, close: @escaping () -> Void) {
        self.init(title: title, mark: intelligent ? .sparkle : .none, trailing: trailing, close: close)
    }

    init(title: Text, mark: Mark, trailing: Text? = nil, close: @escaping () -> Void) {
        self.title = title
        self.mark = mark
        self.trailing = trailing
        self.close = close
    }

    var body: some View {
        HStack(spacing: 8) {
            switch mark {
            case .none: EmptyView()
            case .sparkle: FlixSparkle(size: 12)
            case .robi: FlixRobiBadge()
            }
            title
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            if let trailing {
                trailing.font(.system(size: 11.5)).foregroundStyle(FlixStyle.faint).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
            FlixCloseButton(action: close)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// The 30-point text field of the sheets: a faint fill and a hairline that turns accent with focus.
struct FlixSheetField: View {
    @Binding var text: String
    let prompt: Text
    var focus: FocusState<Bool>.Binding
    var submit: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        TextField(text: $text) { prompt }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused(focus)
            .onSubmit(submit)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(FlixStyle.field, in: shape)
            .overlay(shape.strokeBorder(focus.wrappedValue ? Color.accentColor.opacity(0.7) : FlixStyle.outline,
                                        lineWidth: focus.wrappedValue ? 1 : 0.5))
            .overlay(shape.inset(by: -2).strokeBorder(Color.accentColor.opacity(focus.wrappedValue ? 0.25 : 0), lineWidth: 2))
            .animation(FlixMotion.hover, value: focus.wrappedValue)
    }
}

/// A capsule suggestion chip: a question for Robi, an example sentence.
struct FlixChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlixHover { hovered in
            configuration.label
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .foregroundStyle(.primary)
                .background(hovered ? FlixStyle.chipHover : FlixStyle.chip, in: .capsule)
                .opacity(configuration.isPressed ? 0.65 : 1)
                .contentShape(.capsule)
                .contentShape(.focusEffect, .capsule)
        }
    }
}

/// A quiet line under a sheet's content when something went wrong or there is nothing to do.
struct FlixSheetNote: View {
    let text: Text
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = .orange

    var body: some View {
        Label { text.fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

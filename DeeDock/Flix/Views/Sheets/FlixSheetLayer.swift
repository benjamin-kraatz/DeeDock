import SwiftUI

/// Shows the current sheet over the list: Tidy and New Smart Filter drop from the top, Ask Robi
/// rises from the bottom, Rename sits at the top. A click on the dimmed list closes it.
struct FlixSheetLayer: View {
    let state: FlixPanelState

    var body: some View {
        ZStack(alignment: alignment) {
            if state.sheet != nil {
                Color.black.opacity(0.12)
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
        .animation(state.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.84),
                   value: state.sheet)
    }

    private var alignment: Alignment {
        if case .askRobi = state.sheet { return .bottom }
        return .top
    }

    private var transition: AnyTransition {
        if state.reduceMotion { return .opacity }
        return .opacity.combined(with: .offset(y: alignment == .top ? -10 : 10)).combined(with: .scale(scale: 0.97))
    }
}

/// The sheet's surface: solid, rounded, shadowed.
struct FlixSheetChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}

/// A sheet's title row with its close button.
struct FlixSheetTitle: View {
    let title: Text
    var intelligent = false
    var trailing: Text?
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if intelligent { FlixSparkle(size: 12) }
            title.font(.system(size: 13.5, weight: .semibold))
            if let trailing { trailing.font(.system(size: 11.5)).foregroundStyle(.tertiary) }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(.flixDismiss))
        }
    }
}

import SwiftUI

/// The search field at the top of the key display. It takes focus as Harbor opens; typing filters
/// every display by window title and app name.
struct HarborSearchField: View {
    @Bindable var session: HarborSession
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(text: $session.query.animation(session.reduceMotion ? HarborStyle.fade : HarborStyle.motion)) {
                Text(.harborSearchPrompt)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($focused)
        }
        .padding(.horizontal, 12)
        .frame(width: 340, height: 36)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(session.reduceTransparency
                      ? AnyShapeStyle(colorScheme == .dark ? Color(white: 0.17) : Color.white)
                      : AnyShapeStyle(.regularMaterial))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.09), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        // The panel becomes key just after it appears; focus once the grid is open.
        .onChange(of: session.showsGrid, initial: true) { _, open in if open { focused = true } }
        .accessibilityLabel(Text(.harborSearchPrompt))
    }
}

import SwiftUI

/// "Unpinned Notes · Undo", shown above the dock for five seconds after a pin is dragged off.
///
/// Follows `HubFilesSidebarUndoToast`: glass that turns opaque under Reduce Transparency, a
/// short rise on a spring, and an accessibility action that does what the button does.
struct DockUnpinUndoToast: View {
    /// The app name, supplied by macOS and never translated.
    let appName: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(.dockUnpinnedToast(appName: appName))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            DockUnpinUndoButton(action: undo)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .modifier(DockUnpinUndoToastBackground())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(.dockUnpinUndo), undo)
    }
}

/// The "Undo" chip. Its fill brightens under the pointer.
private struct DockUnpinUndoButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(.dockUnpinUndo)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.primary.opacity(hovered ? 0.2 : 0.12), in: .rect(cornerRadius: 7, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}

/// The system material, or an opaque fill under Reduce Transparency.
private struct DockUnpinUndoToastBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    shape.fill(scheme == .dark ? Color(red: 0.11, green: 0.114, blue: 0.137) : Color(white: 0.98))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay { shape.strokeBorder(.primary.opacity(0.19), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.4), radius: 15, y: 12)
    }
}

#Preview("Unpin undo toast") {
    DockUnpinUndoToast(appName: "Notes") {}
        .padding(30)
}

#Preview("Unpin undo toast · long name, light") {
    DockUnpinUndoToast(appName: "Microsoft Remote Desktop Beta Preview Edition") {}
        .frame(width: 360)
        .padding(30)
        .preferredColorScheme(.light)
}

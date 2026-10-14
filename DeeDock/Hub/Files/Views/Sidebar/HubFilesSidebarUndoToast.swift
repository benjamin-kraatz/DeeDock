import SwiftUI

/// "Removed “kuki” from the sidebar · ⌘Z · Undo", floating above the status bar for five seconds
/// after a sidebar row is removed.
///
/// It rises 10 pt into place on a short spring and sinks back out; a second removal while it
/// shows swaps the text in place.
struct HubFilesSidebarUndoToast: View {
    let sidebar: HubFilesSidebarModel

    var body: some View {
        ZStack {
            if let offer = sidebar.undo {
                HubFilesSidebarUndoToastContent(title: offer.title) { sidebar.undoRemoval() }
                    .id(offer.token)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .offset(y: 6))))
            }
        }
        .animation(HubFilesMotion.animation(.spring(response: 0.34, dampingFraction: 0.82)), value: sidebar.undo?.token)
    }
}

private struct HubFilesSidebarUndoToastContent: View {
    let title: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(.hubFilesSidebarRemovedToast(title))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "⌘Z")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            HubFilesSidebarUndoButton(action: undo)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .modifier(HubFilesToastBackground())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(.hubFilesSidebarUndo), undo)
    }
}

/// The accent "Undo" chip; its fill turns to the accent selection under the pointer.
private struct HubFilesSidebarUndoButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let theme = HubFilesTheme(scheme)
        Button(action: action) {
            Text(.hubFilesSidebarUndo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(hovered ? theme.accentSelection : theme.chipHighlight,
                            in: .rect(cornerRadius: 7, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.15)), value: hovered)
    }
}

/// The toast's glass: the system material, or an opaque fill under Reduce Transparency.
private struct HubFilesToastBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    shape.fill(scheme == .dark ? Color(red: 0.157, green: 0.161, blue: 0.196) : Color(white: 0.98))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay { shape.strokeBorder(HubFilesTheme(scheme).strongLine, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
    }
}

#Preview("Undo toast") {
    HubFilesSidebarUndoToastContent(title: "kuki") {}
        .padding(30)
}

#Preview("Undo toast · long name, light") {
    HubFilesSidebarUndoToastContent(title: "Lightroom export 2026-10 (Moodboard, Screenshots and more)") {}
        .padding(30)
        .frame(width: 520)
        .preferredColorScheme(.light)
}

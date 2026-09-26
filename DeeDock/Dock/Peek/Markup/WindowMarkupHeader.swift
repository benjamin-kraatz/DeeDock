import SwiftUI

/// The strip above the picture: which window this is, how sharp the picture is, the palette's
/// style controls, and undo/redo. The window's own close button sits to its left.
struct WindowMarkupHeader: View {
    let session: WindowMarkupSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var document: WindowMarkupDocument { session.document }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = session.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                status
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            WindowMarkupStyleControls(document: document)
            Divider().frame(height: 18)
            // Typing into a text mark keeps ⌘Z for the text field.
            let typing = document.editingTextID != nil
            HStack(spacing: 2) {
                Button(.markupUndo, systemImage: "arrow.uturn.backward") { document.undo() }
                    .modifier(WindowMarkupShortcut(key: "z", modifiers: .command, enabled: !typing))
                    .disabled(!document.canUndo)
                Button(.markupRedo, systemImage: "arrow.uturn.forward") { document.redo() }
                    .modifier(WindowMarkupShortcut(key: "z", modifiers: [.command, .shift], enabled: !typing))
                    .disabled(!document.canRedo)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .medium))
        }
        // Room for the traffic-light close button the transparent title bar leaves in place.
        .padding(.leading, 68)
        .padding(.trailing, 16)
        .frame(height: WindowMarkupLayout.headerHeight)
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 5) {
            switch session.captureState {
            case .capturing:
                ProgressView().controlSize(.mini)
                Text(.markupStatusCapturing)
            case .fresh(let date):
                Image(systemName: "sparkles").symbolEffect(.bounce, value: date)
                Text(.markupStatusFresh(width: Int(document.size.width), height: Int(document.size.height)))
            case .previewOnly:
                Image(systemName: "photo")
                Text(.markupStatusPreview)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session.captureState)
    }
}

import AppKit
import SwiftUI

/// The staged batch and the grip on it, as one object.
///
/// A separate "drag these files" well below the list said the same thing twice and looked like a
/// place to drop something, which this panel has nothing to accept. Here the list *is* the handle:
/// the whole card is the drag origin, the pointer turns into an open hand over it and a closed one
/// while it is held, and the card lifts on hover the way a stack of paper does when a hand nears
/// it. Only the Quick Look buttons keep their own clicks, so a look is never a grab.
struct WindowFileHandoffBatchCard: View {
    let state: WindowFileHandoffState
    /// Destination app color, shared with the header and the action rows.
    let tint: Color
    let preview: (WindowFileHandoffFile) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var grabbing = false

    private var enabled: Bool { state.valid && !state.busy }
    /// Hovering or holding: both mean the batch is about to move.
    private var lifted: Bool { enabled && (hovering || grabbing) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            LazyVStack(spacing: 2) {
                ForEach(state.files) { file in
                    row(file)
                }
            }
            .padding(6)
            Text(.fileRouteDragHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 11)
                .overlay { source }
        }
        .background(tint.opacity(lifted ? 0.13 : 0.06), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(enabled ? (lifted ? 0.55 : 0.22) : 0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: lifted ? 9 : 0, y: lifted ? 3 : 0)
        .opacity(enabled ? 1 : 0.6)
        .onHover { inside in
            hovering = inside
            // set() rather than push/pop: SwiftUI hover exits are not guaranteed to pair up, and an
            // unbalanced cursor stack outlives this panel.
            if inside, enabled { NSCursor.openHand.set() } else if !inside { NSCursor.arrow.set() }
        }
        .onDisappear { NSCursor.arrow.set() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: lifted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.fileRouteDragFiles))
        .accessibilityHint(Text(.fileRouteDragHelp))
    }

    private var header: some View {
        HStack(spacing: 8) {
            stack
            Text(.fileRouteFilesTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(.fileRouteFileCount(state.files.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 8)
            Label { Text(.fileRouteDragFiles) } icon: { Image(systemName: "hand.draw.fill") }
                .font(.caption.weight(.medium))
                .foregroundStyle(enabled ? tint : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.opacity(lifted ? 0.22 : 0.12), in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .overlay { source }
        .accessibilityElement(children: .combine)
    }

    /// The leading icons fanned the way `WindowFileDragSession` fans the dragging items, so the
    /// card shows what the pointer will be carrying.
    private var stack: some View {
        ZStack {
            ForEach(Array(state.files.prefix(3).enumerated()).reversed(), id: \.element.id) { index, file in
                Image(nsImage: file.icon)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(Double(index) * -5))
                    .offset(x: CGFloat(index) * (lifted ? 4 : 3), y: CGFloat(index) * (lifted ? -3 : -2))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            }
        }
        .frame(width: 28, height: 22, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    private func row(_ file: WindowFileHandoffFile) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: file.icon)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !file.location.isEmpty {
                        Text(verbatim: file.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .contentShape(.rect)
            // Layered under the button, and covering only the row's leading content, so Quick Look
            // keeps its own clicks while everything else in the row starts the drag.
            .overlay { source }
            Button(.fileRoutePreview, systemImage: "eye") { preview(file) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!enabled)
                .help(Text(.fileRoutePreview))
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(lifted ? AnyShapeStyle(.quaternary.opacity(0.45)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: file.name))
    }

    /// The drag origin. It answers only left mouse down, so hover, scrolling and the Quick Look
    /// buttons keep working while the card is also the handle on the batch.
    private var source: some View {
        ShelfItemDragSourceView(
            id: state.dragID, enabled: enabled,
            press: { _, _ in
                guard enabled else { return }
                grabbing = true
                NSCursor.closedHand.set()
            },
            click: { grabbing = false; NSCursor.openHand.set() },
            cancelClick: { grabbing = false; NSCursor.arrow.set() },
            open: {},
            begin: { view, event in
                grabbing = false
                WindowFileDragSession.begin(state.documents, from: view, event: event)
            }
        )
    }
}

#if DEBUG
#Preview("Ready") {
    let state = WindowFileHandoffState.previewState()
    state.busy = false
    state.valid = true
    return WindowFileHandoffBatchCard(state: state, tint: .accentColor, preview: { _ in })
        .padding(26).frame(width: 540)
}

#Preview("Single file, unusable batch") {
    let state = WindowFileHandoffState.previewState(urls: [URL(fileURLWithPath: "/Preview/Unavailable.txt")])
    state.busy = false
    state.valid = false
    return WindowFileHandoffBatchCard(state: state, tint: .teal, preview: { _ in })
        .padding(26).frame(width: 540)
}
#endif

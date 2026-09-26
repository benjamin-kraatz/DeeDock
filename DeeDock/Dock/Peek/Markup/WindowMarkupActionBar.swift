import SwiftUI

/// The ways a markup leaves the editor, grouped by what they produce.
///
/// First the picture: copy, save, share, shelf, drag. Then its text: Live Text, copy, search. Last
/// the picture's own state: frame, crop, recapture. Labels give way to icons when the window is
/// narrow, and the whole bar is one glass capsule so it reads as a single instrument.
struct WindowMarkupActionBar: View {
    let session: WindowMarkupSession
    let opaque: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shareAnchor: CGRect = .zero

    private var document: WindowMarkupDocument { session.document }
    private var ready: Bool { session.image != nil }
    /// Command shortcuts step aside while a text mark is being typed, so ⌘C copies typed text.
    private var typing: Bool { document.editingTextID != nil }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(labels: true)
            bar(labels: false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: WindowMarkupLayout.footerHeight)
        .padding(.horizontal, 16)
    }

    private func bar(labels: Bool) -> some View {
        HStack(spacing: 4) {
            copyButton(labels: labels)
            action(.markupSave, symbol: "square.and.arrow.down", labels: labels, shortcut: "s") { session.save() }
            action(.markupShare, symbol: "square.and.arrow.up", labels: labels) {
                guard let view = session.hostWindow?()?.contentView else { return }
                // SwiftUI's global space is the window's top-left; AppKit views measure from the bottom.
                let rect = CGRect(x: shareAnchor.minX, y: view.bounds.height - shareAnchor.maxY,
                                  width: shareAnchor.width, height: shareAnchor.height)
                session.share(from: view, rect: rect)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { shareAnchor = $0 }
            if session.shelfAvailable, session.stageOnShelf != nil {
                action(.markupSendToShelf, symbol: "tray.and.arrow.down", labels: labels) { session.sendToShelf() }
            }
            dragGrip(labels: labels)
            separator
            liveTextToggle(labels: labels)
            action(.markupCopyText, symbol: "text.viewfinder", labels: labels, shortcut: "c", modifiers: [.command, .shift]) {
                session.copyText()
            }
            .disabled(session.recognizing)
            action(.markupSearchWeb, symbol: "magnifyingglass", labels: labels) { session.searchWeb() }
                .disabled(session.recognizing)
            separator
            frameToggle(labels: labels)
            if document.crop != nil {
                action(.markupResetCrop, symbol: "crop.rotate", labels: labels) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { document.crop = nil }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            action(.markupRecapture, symbol: "camera.badge.clock", labels: labels) { session.recapture() }
                .disabled(session.captureState == .capturing || session.window.isMinimized)
            if document.hasMarks {
                action(.markupClearAll, symbol: "trash", labels: labels) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { document.clear() }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(WindowMarkupChrome(opaque: opaque, radius: 22))
        .disabled(!ready)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1), value: document.crop != nil)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1), value: document.hasMarks)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.markupActionsAccessibility))
    }

    private var separator: some View {
        Rectangle().fill(.separator).frame(width: 1, height: 18).padding(.horizontal, 5).accessibilityHidden(true)
    }

    /// Copy is the most common exit, so it is the one prominent control. Its icon flips to a check
    /// for a moment after a copy, which is confirmation enough without a dialog.
    private func copyButton(labels: Bool) -> some View {
        let copied = session.notice?.message.key == LocalizedStringResource.markupNoticeCopied.key
            || session.notice?.message.key == LocalizedStringResource.markupNoticeTextCopied.key
        return Button {
            session.copy()
        } label: {
            Label { Text(.markupCopy) } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(labels ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, labels ? 12 : 8)
            .frame(height: 30)
        }
        .buttonStyle(.glassProminent)
        .tint(session.tint)
        .modifier(WindowMarkupShortcut(key: "c", modifiers: .command, enabled: !typing))
        .help(Text(.markupCopyHelp))
    }

    private func action(_ title: LocalizedStringResource, symbol: String, labels: Bool,
                        shortcut: KeyEquivalent? = nil, modifiers: EventModifiers = .command,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .labelStyle(labels ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, labels ? 10 : 8)
                .frame(height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .modifier(WindowMarkupShortcut(key: shortcut, modifiers: modifiers, enabled: !typing))
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    private func liveTextToggle(labels: Bool) -> some View {
        toggle(.markupLiveText, symbol: "text.viewfinder", labels: labels, on: document.liveText,
               help: .markupLiveTextHelp) {
            document.finishText()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { document.liveText.toggle() }
        }
    }

    private func frameToggle(labels: Bool) -> some View {
        toggle(.markupFrame, symbol: "rectangle.inset.filled", labels: labels, on: document.framed,
               help: .markupFrameHelp) { document.framed.toggle() }
    }

    private func toggle(_ title: LocalizedStringResource, symbol: String, labels: Bool, on: Bool,
                        help: LocalizedStringResource, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .labelStyle(labels ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? AnyShapeStyle(session.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, labels ? 10 : 8)
                .frame(height: 30)
                .background(on ? AnyShapeStyle(session.tint.opacity(0.16)) : AnyShapeStyle(.clear), in: .capsule)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    /// Drag this out to drop the finished picture into another app or Finder.
    private func dragGrip(labels: Bool) -> some View {
        Label { Text(.markupDrag) } icon: { Image(systemName: "hand.draw") }
            .labelStyle(labels ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, labels ? 10 : 8)
            .frame(height: 30)
            .contentShape(.rect)
            .onDrag { session.dragProvider() ?? NSItemProvider() }
            .pointerStyle(.grabIdle)
            .help(Text(.markupDragHelp))
            .accessibilityLabel(Text(.markupDrag))
            .accessibilityHint(Text(.markupDragHelp))
    }
}

/// Applies a command shortcut only while `enabled`, so typing into a text mark keeps its own keys.
struct WindowMarkupShortcut: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: EventModifiers
    let enabled: Bool

    func body(content: Content) -> some View {
        if let key, enabled {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}

/// Type-erases label styles so one label can switch between titled and icon-only layouts.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

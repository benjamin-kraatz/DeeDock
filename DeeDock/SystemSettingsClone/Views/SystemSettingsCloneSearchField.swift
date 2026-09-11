import AppKit
import SwiftUI

/// Keys the search field forwards instead of handling as text editing.
enum SystemSettingsCloneSearchCommand {
    case moveUp, moveDown, submit, cancel
}

/// Large search capsule. Arrow keys, Return, and Escape drive the result list while
/// the caret stays in the field, the way Spotlight works.
struct SystemSettingsCloneSearchField: View {
    @Binding var text: String
    /// Increment to move keyboard focus into the field, for example from ⌘F.
    let focusRequest: Int
    let onCommand: (SystemSettingsCloneSearchCommand) -> Void
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .accessibilityHidden(true)
            SystemSettingsCloneSearchTextField(
                text: $text,
                placeholder: String(localized: .systemSettingsCloneSearchPrompt),
                focusRequest: focusRequest,
                isFocused: $isFocused,
                onCommand: onCommand
            )
            .frame(height: 22)
            if text.isEmpty {
                SystemSettingsCloneKeyCap(label: "⌘F")
                    .transition(.opacity)
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.systemSettingsCloneClearSearch))
                .help(Text(.systemSettingsCloneClearSearch))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(isFocused ? 0.55 : 0), lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
    }
}

/// Borderless `NSTextField` so movement commands can be intercepted before the field editor
/// consumes them. SwiftUI's `TextField` does not expose `moveUp:`/`moveDown:` on macOS.
private struct SystemSettingsCloneSearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequest: Int
    @Binding var isFocused: Bool
    let onCommand: (SystemSettingsCloneSearchCommand) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusReportingTextField {
        let field = FocusReportingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16, weight: .regular)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.onFocusChange = { focused in context.coordinator.parent.isFocused = focused }
        return field
    }

    func updateNSView(_ field: FocusReportingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            // The field may not be in a window yet on the first pass.
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SystemSettingsCloneSearchTextField
        var handledFocusRequest: Int?

        init(_ parent: SystemSettingsCloneSearchTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onCommand(.moveUp)
            case #selector(NSResponder.moveDown(_:)): parent.onCommand(.moveDown)
            case #selector(NSResponder.insertNewline(_:)): parent.onCommand(.submit)
            case #selector(NSResponder.cancelOperation(_:)): parent.onCommand(.cancel)
            default: return false
            }
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }

    /// Reports when the field editor takes over, which `NSTextField` does not publish itself.
    final class FocusReportingTextField: NSTextField {
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusChange?(true) }
            return accepted
        }
    }
}

#if DEBUG
#Preview("Search field") {
    @Previewable @State var text = ""
    SystemSettingsCloneSearchField(text: $text, focusRequest: 0, onCommand: { _ in })
        .padding(30)
        .frame(width: 560)
}
#endif

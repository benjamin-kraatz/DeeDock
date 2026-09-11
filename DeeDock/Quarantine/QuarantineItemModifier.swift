import AppKit
import SwiftUI

/// Adds a blocking stamp target above existing native drag/menu bridges. While marked, the
/// original content also loses accessibility actions; release remains an explicit action.
struct QuarantineItemModifier: ViewModifier {
    let id: String
    let url: URL
    let name: String
    var eligible = true
    private let store = QuarantineStore.shared
    private let stamp = QuarantineStampController.shared

    private var marked: Bool { store.contains(id, url: url) }
    private var intercepts: Bool { marked || (eligible && stamp.armed) }

    func body(content: Content) -> some View {
        content
            .disabled(intercepts)
            .accessibilityHidden(intercepts)
            .saturation(marked ? 0.15 : 1)
            .opacity(marked ? 0.65 : 1)
            .overlay(alignment: .bottomTrailing) {
                if marked {
                    Image("QuarantineInk").resizable().scaledToFit()
                        .frame(width: 28, height: 28).allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if intercepts {
                    QuarantineHitTarget(action: { activate(anchor: $0) })
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: name))
                        .accessibilityValue(Text(marked ? .quarantineMarked : .quarantineArm))
                        .accessibilityHint(Text(stamp.armed ? .quarantineGestureHelp : .quarantineNoticeHint))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { activate() }
                        .help(Text(marked ? .quarantineMarked : .quarantineArm))
                }
            }
    }

    private func activate(anchor: CGRect? = nil) {
        if stamp.armed {
            stamp.stamp(id: id, url: url, name: name)
        } else if marked {
            QuarantineNoticeController.shared.show(near: anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero))
        }
    }
}

private struct QuarantineHitTarget: NSViewRepresentable {
    let action: (CGRect) -> Void
    func makeNSView(context: Context) -> TargetView { TargetView() }
    func updateNSView(_ view: TargetView, context: Context) {
        view.action = action
        QuarantineStampController.shared.registerTarget(view)
    }
    static func dismantleNSView(_ view: TargetView, coordinator: ()) {
        view.action = nil
        QuarantineStampController.shared.unregisterTarget(view)
    }

    final class TargetView: NSView {
        var action: ((CGRect) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            action?(window.convertToScreen(convert(bounds, to: nil)))
        }
        override func rightMouseDown(with event: NSEvent) { }
        override func mouseDragged(with event: NSEvent) { }
    }
}

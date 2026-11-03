import AppKit
import SwiftUI

/// The "Something's off right now…" picker: a small key panel near the top of the display under the pointer.
///
/// Opening it is a deliberate menu action, so it takes keyboard focus through `ExplicitWindowPresenter`, as Focus
/// Dock does, and hands focus back to the previous app when it closes. Escape, the close button, or focus moving to
/// another window dismisses it; the coordinator decides what that means and calls `close()`.
///
/// Owns one local key monitor and, after focus moves away, one short delayed check. Both end in `close()`.
@MainActor
final class AppHealthPickerPanelController: AppHealthPickerPresenting {
    /// A focus change can bounce through another DOKK window while activation settles; dismissing only if the
    /// picker is still not key after this delay keeps that bounce from closing it.
    private static let resignGrace: Duration = .milliseconds(250)
    private static let topInset: CGFloat = 8

    var picked: ((AppHealthPickerEntry) -> Void)?
    var dismissed: (() -> Void)?

    private let panel = AppHealthPanel.make(level: .floating)
    private let model: AppHealthPickerModel
    private var content: AppHealthPanelContentView<AppHealthPickerView>?
    private var size: CGSize
    /// The horizontal centre and the top edge the panel keeps while its height changes, in AppKit screen
    /// coordinates (y up), with the display's visible frame for clamping.
    private let centerX: CGFloat
    private let top: CGFloat
    private let visibleFrame: CGRect
    private var localMonitor: Any?
    private var resignCheck: Task<Void, Never>?
    private var previousApplication: NSRunningApplication?
    private var focusGeneration: UUID?
    private var presented = false
    private var closed = false
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    init(entries: [AppHealthPickerEntry]) {
        model = AppHealthPickerModel(entries: entries)
        // The display under the pointer: the menu-bar item the person just clicked is there.
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        centerX = pointer.x
        top = visibleFrame.maxY - Self.topInset
        size = CGSize(width: AppHealthPickerView.width, height: 200)

        model.pick = { [weak self] entry in self?.picked?(entry) }
        model.close = { [weak self] in self?.dismissed?() }
        let content = AppHealthPanelContentView(rootView: AppHealthPickerView(model: model) { [weak self] size in
            // Reported during SwiftUI layout; resizing the window from inside that pass would re-enter it.
            DispatchQueue.main.async { self?.contentSizeChanged(size) }
        })
        let fitting = content.hosting.fittingSize
        if fitting.width > 0, fitting.height > 0 { size = fitting }
        self.content = content
        panel.contentView = content
        panel.acceptsKeyboardFocus = true
        panel.becameKey = { [weak self] in self?.becameKey() }
        panel.resignedKey = { [weak self] in self?.resignedKey() }
        panel.setFrame(frame(for: size), display: false)
    }

    /// Shows the picker and asks for keyboard focus. Again on a second menu click.
    func present() {
        guard !closed else { return }
        if !presented {
            presented = true
            previousApplication = NSWorkspace.shared.frontmostApplication
            installMonitor()
        }
        ExplicitWindowPresenter.shared.present(panel)
        focusGeneration = ExplicitWindowPresenter.shared.generation
    }

    func showQuestion(_ session: AppHealthLabelSession) {
        model.question = session
        session.setKeyboardActive(panel.isKeyWindow)
    }

    func close() {
        guard !closed else { return }
        closed = true
        resignCheck?.cancel()
        resignCheck = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        panel.becameKey = nil
        panel.resignedKey = nil
        model.pick = nil
        model.close = nil
        picked = nil
        dismissed = nil
        ExplicitWindowPresenter.shared.cancel(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        content = nil
        restorePreviousApplication()
    }

    // MARK: - Focus

    private func becameKey() {
        resignCheck?.cancel()
        resignCheck = nil
        model.question?.setKeyboardActive(true)
        model.requestFocus()
    }

    private func resignedKey() {
        model.question?.setKeyboardActive(false)
        resignCheck?.cancel()
        resignCheck = Task { [weak self] in
            do { try await Task.sleep(for: Self.resignGrace) } catch { return }
            guard let self, !closed, !panel.isKeyWindow else { return }
            dismissed?()
        }
    }

    /// DOKK was activated to give the picker focus. If it still is and no other DOKK window took over, hand focus
    /// back to the app the person was using.
    private func restorePreviousApplication() {
        defer { previousApplication = nil }
        guard let previousApplication, !previousApplication.isTerminated,
              previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              focusGeneration == ExplicitWindowPresenter.shared.generation, NSApp.isActive else { return }
        previousApplication.activate(options: [])
    }

    // MARK: - Keys

    /// Routes keys before the filter field sees them: the arrows and Return drive the list, Escape closes, and a
    /// picked app's question gets the shared labelling keys. Everything else types into the filter.
    private func installMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, !closed, event.window === panel else { return event }
            if let question = model.question {
                return AppHealthLabelKeyboard.handle(event, session: question) ? nil : event
            }
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            switch event.keyCode {
            case AppHealthLabelKeyboard.KeyCode.escape:
                dismissed?()
            case AppHealthLabelKeyboard.KeyCode.down:
                model.moveHighlight(by: 1)
            case AppHealthLabelKeyboard.KeyCode.up:
                model.moveHighlight(by: -1)
            case AppHealthLabelKeyboard.KeyCode.returnKey, AppHealthLabelKeyboard.KeyCode.enter:
                model.pickHighlighted()
            default:
                return event
            }
            return nil
        }
    }

    // MARK: - Placement

    /// Follows the content's height as the list filters or a picked app's question replaces it. The window eases
    /// to the new frame while the card, held against the top edge, unfolds downward; Reduce Motion jumps.
    private func contentSizeChanged(_ newSize: CGSize) {
        guard !closed, newSize.width > 0, newSize.height > 0,
              abs(newSize.width - size.width) > 0.5 || abs(newSize.height - size.height) > 0.5 else { return }
        size = newSize
        let frame = frame(for: size)
        guard !reduceMotion, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Centred under the pointer and hanging from just below the menu bar, clamped into the visible frame. AppKit
    /// screen coordinates are y up, so the origin is the top minus the height.
    private func frame(for size: CGSize) -> CGRect {
        let frame = CGRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        return AppHealthPromptPlacement.clamp(frame, into: visibleFrame.insetBy(dx: Self.topInset, dy: Self.topInset))
    }
}

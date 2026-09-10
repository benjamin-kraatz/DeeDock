import AppKit
import SwiftUI

/// Small titled window for per-step prepare outcomes. Hover never opens it.
@MainActor
final class WorkspaceRecipeProgressController: NSObject, NSWindowDelegate {
    private let recipes: WorkspaceRecipeCoordinator
    private var window: NSWindow?
    var openSettings: (() -> Void)?

    init(recipes: WorkspaceRecipeCoordinator) {
        self.recipes = recipes
    }

    func show() {
        if let window {
            window.orderFront(nil)
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: .recipeTitle)
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 360, height: 220)
        window.contentViewController = NSHostingController(rootView: WorkspaceRecipeProgressView(
            coordinator: recipes,
            onOpenSettings: { [weak self] in self?.openSettings?() }
        ))
        window.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            let size = CGSize(width: min(440, frame.width), height: min(360, frame.height))
            window.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                   width: size.width, height: size.height), display: false)
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func stop() {
        close()
        openSettings = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if recipes.run?.phase.isActive == true {
            recipes.cancel()
        } else {
            recipes.dismiss()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

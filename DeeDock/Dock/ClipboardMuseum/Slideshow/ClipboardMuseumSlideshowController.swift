import AppKit
import SwiftUI

/// Presents the slideshow in its own native full-screen Space.
///
/// Uses the system full-screen transition rather than a borderless window so Mission Control,
/// the menu bar reveal, and Spaces behave as they do for any app. Leaving full screen by any path
/// (Escape, the green button, a gesture) closes the slideshow.
@MainActor
final class ClipboardMuseumSlideshowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(exhibits: [ClipboardExhibit], startAt id: UUID?, imageURL: @escaping (ClipboardExhibit) -> URL?) {
        window?.close()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.title = String(localized: .clipboardMuseumSlideshow)
        let start = id.flatMap { id in exhibits.firstIndex { $0.id == id } } ?? 0
        window.contentViewController = NSHostingController(rootView: ClipboardMuseumSlideshow(
            exhibits: exhibits, startIndex: start, imageURL: imageURL,
            close: { [weak self] in self?.close() }))
        window.delegate = self
        window.setFrame(frame, display: false)
        self.window = window
        ExplicitWindowPresenter.shared.present(window)
        // Enter full screen after the presenter has made the window key; toggling earlier is ignored.
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let window, window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    /// Animates out of full screen first; `windowDidExitFullScreen` finishes the close.
    func close() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            window.close()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    func stop() {
        window?.close()
    }
}

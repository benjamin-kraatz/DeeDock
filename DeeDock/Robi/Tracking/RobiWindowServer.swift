import AppKit
import ApplicationServices

/// Window identity and live bounds from the window server.
nonisolated enum RobiWindowServer {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// `_AXUIElementGetWindow` maps an AX window to its `CGWindowID`. It is private, but has been
    /// stable for over a decade and is used by AltTab, Rectangle and Hammerspoon. Resolved with
    /// `dlsym` so a future macOS that drops it falls back to frame matching instead of failing to
    /// launch.
    private static let getWindow: GetWindow? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }

    /// The window ID behind an AX window, or nil when it cannot be told apart from another window
    /// of the same app.
    static func windowID(of window: AXUIElement, processIdentifier: pid_t, frame: CGRect) -> CGWindowID? {
        if let getWindow {
            var id: CGWindowID = 0
            if getWindow(window, &id) == .success, id != 0 { return id }
        }
        // Fallback: one on-screen layer-0 window of this app with the same frame. Ambiguous
        // matches are refused rather than sampling the wrong window.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let matches = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = (info[kCGWindowBounds as String] as? [String: Any]).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return false }
            return abs(bounds.minX - frame.minX) < 2 && abs(bounds.minY - frame.minY) < 2
                && abs(bounds.width - frame.width) < 2 && abs(bounds.height - frame.height) < 2
        }
        guard matches.count == 1 else { return nil }
        return matches[0][kCGWindowNumber as String] as? CGWindowID
    }

    /// Live bounds of one window in global top-left points, straight from the window server.
    /// Measured at about 80 µs, cheap enough to call on every drag event.
    static func bounds(of windowID: CGWindowID) -> CGRect? {
        var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(windowID))]
        guard let array = CFArrayCreate(nil, &ids, 1, nil),
              let info = (CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]])?.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) != false,
              let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}

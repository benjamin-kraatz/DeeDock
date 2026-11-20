import AppKit

extension FlixFrontmostContext {
    /// The app and window in front right now, read before Flix Files takes focus.
    ///
    /// The window comes from the window server's on-screen list: the first normal-layer window owned
    /// by the app. This reads no window contents and needs no permission; the title is only present
    /// with Screen Recording access. Nil when DOKK itself is in front and `fallback` is nil.
    ///
    /// - Parameter fallback: The last external app, used when DOKK is frontmost (a dock click does
    ///   not activate DOKK, but the shortcut can arrive while Settings is open).
    @MainActor
    static func capture(fallback: NSRunningApplication?) -> FlixFrontmostContext? {
        let own = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        guard let app = front?.processIdentifier == own ? fallback : front, !app.isTerminated,
              app.processIdentifier != own else { return nil }
        let pid = app.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let window = list.first { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0
        }
        return FlixFrontmostContext(processIdentifier: pid, bundleIdentifier: app.bundleIdentifier,
                                    applicationName: app.localizedName,
                                    windowID: (window?[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                                    windowTitle: window?[kCGWindowName as String] as? String,
                                    capturedAt: .now)
    }
}

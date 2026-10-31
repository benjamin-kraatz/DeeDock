import AppKit
import ApplicationServices
import OSLog

/// Reads and presses an application's rows in the macOS Dock's menu.
///
/// macOS has no public way to ask another application for its Dock menu: the Dock fetches it over
/// a private channel. The only route is to open the menu on the Dock's own tile through
/// Accessibility, read it, and dismiss it. The menu is on screen for that moment, so callers read
/// only while the Dock is tucked away, where macOS does not draw it. With a visible Dock every
/// read flashes for 30–60 ms.
///
/// The actor serializes access because the Dock shows one menu at a time. Methods block on the
/// Dock's replies, and Accessibility handles never leave the actor. Nothing here asks for
/// permission: without Accessibility access there is simply nothing to read.
actor SystemDockMenuReader {
    /// A right-click waits for the read, and the first one after launch has taken 236 ms.
    private static let readDeadline: TimeInterval = 0.3
    /// How long a press may wait for the menu, which has no one waiting on it to appear.
    private static let pressDeadline: TimeInterval = 1
    /// How long a menu that missed the deadline is watched for so it can still be dismissed.
    private static let lateMenuWindow: TimeInterval = 0.5
    /// Set on every element, because Accessibility's default is six seconds.
    private static let messagingTimeout: Float = 0.25
    /// A hung application must not hold up its own context menu.
    private static let windowMessagingTimeout: Float = 0.1
    /// Deep enough for real menus, while a pathological one still ends.
    private static let maximumDepth = 4

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "SystemDockMenu")

    /// Reads the rows an application added to its Dock menu.
    ///
    /// Opens and dismisses the Dock's menu. Returns nothing when the app has no tile, when
    /// Accessibility access is missing, or when the deadline passes, so a failed read leaves the
    /// caller's menu as it would otherwise be.
    /// - Parameters:
    ///   - applicationURL: The bundle URL matched against the Dock's tiles.
    ///   - processes: The application's running processes, whose windows are left out.
    func applicationEntries(applicationURL: URL, processes: [pid_t]) -> [SystemDockMenuEntry] {
        guard AXIsProcessTrusted(), let tile = tile(for: applicationURL) else { return [] }
        let deadline = Date().addingTimeInterval(Self.readDeadline)
        guard AXUIElementPerformAction(tile, "AXShowMenu" as CFString) == .success else { return [] }
        guard let menu = openedMenu(on: tile, until: deadline) else {
            Self.logger.notice("The Dock's menu missed the read deadline")
            Task { dismissLateMenu(applicationURL: applicationURL) }
            return []
        }

        let entries = self.entries(in: menu, parentPath: [], until: deadline)
        // This has to run on every path past opening, or the Dock keeps tracking a menu no one sees.
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        guard let entries else {
            Self.logger.notice("Reading the Dock's menu missed the deadline")
            return []
        }
        return SystemDockMenuFilter.applicationEntries(in: entries, windowTitles: windowTitles(of: processes))
    }

    /// Presses the row an entry was read from, which runs the application's own action.
    ///
    /// Reopens the Dock's menu, since the one that was read is gone. Pressing a row in a submenu
    /// works without opening that submenu.
    /// - Returns: Whether the row was found and pressed. It is false when the menu changed since
    ///   the read, in which case nothing is pressed and the menu is dismissed.
    @discardableResult
    func press(_ entry: SystemDockMenuEntry, applicationURL: URL) -> Bool {
        guard AXIsProcessTrusted(), let tile = tile(for: applicationURL),
              AXUIElementPerformAction(tile, "AXShowMenu" as CFString) == .success,
              let menu = openedMenu(on: tile, until: Date().addingTimeInterval(Self.pressDeadline)) else { return false }

        guard let row = row(at: entry.path, in: menu) else {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            Self.logger.notice("The Dock's menu changed before a row could be pressed")
            return false
        }
        // Pressing dismisses the menu, so only a failed press needs cancelling.
        guard AXUIElementPerformAction(row, kAXPressAction as CFString) == .success else {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            return false
        }
        return true
    }

    /// Matches by bundle URL because tile titles vary with localization and can repeat.
    private func tile(for applicationURL: URL) -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let path = applicationURL.standardizedFileURL.path
        for list in children(of: AXUIElementCreateApplication(dock.processIdentifier)) {
            for tile in children(of: list) {
                guard let url = attribute(kAXURLAttribute, of: tile) as? URL else { continue }
                if url.standardizedFileURL.path == path { return tile }
            }
        }
        return nil
    }

    /// The Dock reports success before it attaches the menu, so its arrival has to be polled for.
    private func openedMenu(on tile: AXUIElement, until deadline: Date) -> AXUIElement? {
        while Date() < deadline {
            if let menu = children(of: tile).first { return menu }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return nil
    }

    /// Catches a menu that opened after its reader gave up, which the Dock would otherwise hold.
    private func dismissLateMenu(applicationURL: URL) {
        guard let tile = tile(for: applicationURL),
              let menu = openedMenu(on: tile, until: Date().addingTimeInterval(Self.lateMenuWindow)) else { return }
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    /// Returns nil past the deadline, since a partial menu would pass for a complete one.
    private func entries(in menu: AXUIElement, parentPath: [SystemDockMenuEntry.Step], until deadline: Date) -> [SystemDockMenuEntry]? {
        var entries: [SystemDockMenuEntry] = []
        for (index, row) in children(of: menu).enumerated() {
            guard Date() < deadline else { return nil }
            let title = attribute(kAXTitleAttribute, of: row) as? String ?? ""
            let path = parentPath + [SystemDockMenuEntry.Step(index: index, title: title)]
            var rows: [SystemDockMenuEntry] = []
            // A row's only child is the submenu that holds the next level.
            if parentPath.count < Self.maximumDepth, let submenu = children(of: row).first {
                guard let nested = self.entries(in: submenu, parentPath: path, until: deadline) else { return nil }
                rows = nested
            }
            let mark = attribute(kAXMenuItemMarkCharAttribute, of: row) as? String
            entries.append(SystemDockMenuEntry(title: title,
                                               isEnabled: attribute(kAXEnabledAttribute, of: row) as? Bool ?? false,
                                               isChecked: mark?.isEmpty == false,
                                               path: path,
                                               children: rows))
        }
        return entries
    }

    private func row(at path: [SystemDockMenuEntry.Step], in menu: AXUIElement) -> AXUIElement? {
        var current = menu
        var match: AXUIElement?
        for step in path {
            let rows = children(of: current)
            guard rows.indices.contains(step.index) else { return nil }
            let row = rows[step.index]
            guard attribute(kAXTitleAttribute, of: row) as? String ?? "" == step.title else { return nil }
            match = row
            if step != path.last {
                guard let submenu = children(of: row).first else { return nil }
                current = submenu
            }
        }
        return match
    }

    private func windowTitles(of processes: [pid_t]) -> Set<String> {
        var titles = Set<String>()
        for process in processes {
            let application = AXUIElementCreateApplication(process)
            AXUIElementSetMessagingTimeout(application, Self.windowMessagingTimeout)
            guard let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] else { continue }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, Self.windowMessagingTimeout)
                if let title = attribute(kAXTitleAttribute, of: window) as? String, !title.isEmpty { titles.insert(title) }
            }
        }
        return titles
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let elements = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
        for child in elements { AXUIElementSetMessagingTimeout(child, Self.messagingTimeout) }
        return elements
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

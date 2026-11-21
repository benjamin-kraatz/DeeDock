import AppKit

/// Works out where a finished drag out of Flix Files landed, as a category.
///
/// macOS tells a drag source only whether a drop was accepted, not where. So at the end of an accepted
/// drag this looks once at the window under the drop point (`CGWindowListCopyWindowInfo`, which needs
/// no permission for owners and bounds; titles are never read) and reduces its app to a
/// `FlixAppCategory`. DOKK's own windows report what the dock said it received
/// (`DockDragCoordinator.flixDropLanded`), or `dock_app`. For a browser, the page kind comes from what
/// "Fits this window" read in the window that was in front, when the drop went to that app; any other
/// browser window is `page` with `other_page`. Runs once per drop, never on the pointer path.
@MainActor
enum FlixDropTargetResolver {
    struct Resolution: Equatable {
        var target: AnalyticsFlixDropTarget
        var category: FlixAppCategory?
        var pageKind: AnalyticsFlixPageKind?
    }

    /// - Parameters:
    ///   - point: The drop point in AppKit screen coordinates (bottom-left origin).
    ///   - dockTarget: What DOKK's dock reported receiving, if the drop was on it.
    ///   - front: The window that was in front when the panel opened, with its reading's page kind.
    static func resolve(at point: CGPoint, dockTarget: AnalyticsFlixDropTarget?,
                        front: (context: FlixFrontmostContext, pageKind: FlixWindowDemand.PageKind?)?) -> Resolution {
        if let dockTarget { return Resolution(target: dockTarget, category: nil, pageKind: nil) }
        guard let owner = ownerOfWindow(at: point) else {
            return Resolution(target: .otherApp, category: FlixAppCategory.none, pageKind: nil)
        }
        if owner == ProcessInfo.processInfo.processIdentifier {
            return Resolution(target: .dockApp, category: nil, pageKind: nil)
        }
        let app = NSRunningApplication(processIdentifier: owner)
        if app?.bundleIdentifier == "com.apple.dock" {
            return Resolution(target: .dockApp, category: nil, pageKind: nil)
        }
        let category = FlixAppCategory.of(bundleIdentifier: app?.bundleIdentifier, bundleURL: app?.bundleURL)
        switch category {
        case .browser:
            let kind = front.flatMap { $0.context.processIdentifier == owner ? $0.pageKind : nil }
            let pageKind = kind.map { AnalyticsFlixPageKind($0) } ?? .otherPage
            return Resolution(target: pageKind == .uploadForm ? .browserUpload : .page, category: category,
                              pageKind: pageKind)
        case .mail: return Resolution(target: .mailCompose, category: category, pageKind: nil)
        case .chat: return Resolution(target: .chat, category: category, pageKind: nil)
        case .finder: return Resolution(target: .finder, category: category, pageKind: nil)
        default: return Resolution(target: .otherApp, category: category, pageKind: nil)
        }
    }

    /// The process owning the frontmost visible window under `point`. Overlays above the normal
    /// window layer (menus, the menu bar, screenshots in progress) are skipped, except the Dock's and
    /// DOKK's own.
    private static func ownerOfWindow(at point: CGPoint) -> pid_t? {
        // Window server bounds are global top-left points from the primary display's top edge.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: primaryHeight - point.y)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in list {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.contains(flipped) else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            // DOKK's own docks float above normal windows; the faded Flix panel was skipped by its alpha.
            if layer > 0, pid != ProcessInfo.processInfo.processIdentifier,
               NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.dock" { continue }
            return pid
        }
        return nil
    }
}

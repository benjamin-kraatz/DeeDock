import AppKit

/// Matches the display name a banner shows to one installed application.
///
/// macOS gives the banner no bundle identifier, so the name is all there is. Two apps can share a
/// name, and an app can post under a name that matches nothing installed. Only a single,
/// unambiguous match resolves; anything else shows a generic icon and opens nothing.
@MainActor
final class NotificationFeedAppResolver {
    private let running: () -> [ApplicationReference]
    private let installed: () -> [ApplicationReference]
    private var cache: [String: ApplicationReference?] = [:]
    private var icons: [String: NSImage] = [:]

    /// - Parameters:
    ///   - running: Running regular applications, checked first because a sender is usually running.
    ///   - installed: The installed applications the Launcher already indexed.
    init(running: @escaping () -> [ApplicationReference], installed: @escaping () -> [ApplicationReference]) {
        self.running = running
        self.installed = installed
    }

    /// The application a banner's name refers to, or nil when there is no single match.
    func application(named name: String?) -> ApplicationReference? {
        guard let name, !name.isEmpty else { return nil }
        if let cached = cache[name] { return cached }
        let resolved = Self.unique(named: name, in: running()) ?? Self.unique(named: name, in: installed())
        cache[name] = resolved
        return resolved
    }

    /// The application's icon, loaded once per application for as long as the resolver lives.
    func icon(for reference: ApplicationReference) -> NSImage {
        if let icon = icons[reference.id] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: reference.url.path)
        icons[reference.id] = icon
        return icon
    }

    /// Forgets cached matches, for a feed opened after apps were installed or launched.
    func invalidate() {
        cache.removeAll()
    }

    /// Several running instances of one application are still a single match.
    nonisolated static func unique(named name: String, in references: [ApplicationReference]) -> ApplicationReference? {
        let matches = references.filter { $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame }
        guard let first = matches.first, matches.allSatisfy({ $0.id == first.id }) else { return nil }
        return first
    }
}

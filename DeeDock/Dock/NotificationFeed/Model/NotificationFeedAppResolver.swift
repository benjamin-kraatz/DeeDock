import AppKit

/// Matches the display name a banner shows to one installed application.
///
/// macOS gives the banner no bundle identifier, so the name is all there is. Two apps can share a
/// name, and an app can post under a name that matches nothing installed. Only a single,
/// unambiguous match resolves; anything else shows a generic icon and opens nothing.
///
/// There are two resolutions, because a wrong guess costs different things:
/// - ``application(named:)`` serves the row's icon and Open App. It checks running apps first,
///   so a name shared by an installed copy still opens the one the person is using.
/// - ``unambiguousApplication(named:)`` serves auto-clear, which removes entries without being
///   asked. It looks at running and installed apps together and resolves only when exactly one
///   application carries the name.
@MainActor
final class NotificationFeedAppResolver {
    private let running: () -> [ApplicationReference]
    private let installed: () -> [ApplicationReference]
    private var cache: [String: ApplicationReference?] = [:]
    private var unambiguousCache: [String: ApplicationReference?] = [:]
    private var icons: [String: NSImage] = [:]

    /// - Parameters:
    ///   - running: Running regular applications, checked first because a sender is usually running.
    ///   - installed: The installed applications the Launcher already indexed.
    init(running: @escaping () -> [ApplicationReference], installed: @escaping () -> [ApplicationReference]) {
        self.running = running
        self.installed = installed
    }

    /// The application a banner's name refers to for display and Open App, or nil when there is
    /// no single match.
    ///
    /// A unique running match wins even when an installed app shares the name: opening the app
    /// already running is what the person most likely means, and opening is something they asked
    /// for. Only when no running app resolves are installed apps consulted.
    func application(named name: String?) -> ApplicationReference? {
        guard let name, !name.isEmpty else { return nil }
        if let cached = cache[name] { return cached }
        let resolved = Self.unique(named: name, in: running()) ?? Self.unique(named: name, in: installed())
        cache[name] = resolved
        return resolved
    }

    /// The application a banner's name refers to for auto-clear, or nil when any other running or
    /// installed application shares the name.
    ///
    /// Running and installed apps are pooled and deduplicated by ``ApplicationReference/id``, so a
    /// running app and its own installed bundle count once, while two different apps named
    /// "Notes" stay ambiguous even when only one of them is running.
    func unambiguousApplication(named name: String) -> ApplicationReference? {
        guard !name.isEmpty else { return nil }
        if let cached = unambiguousCache[name] { return cached }
        let resolved = Self.unique(named: name, in: running() + installed())
        unambiguousCache[name] = resolved
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
        unambiguousCache.removeAll()
    }

    /// The one application named `name` in `references`, matched case-insensitively.
    ///
    /// Matches that share an ``ApplicationReference/id`` are one application, so several running
    /// instances, or a running app listed again among installed ones, still resolve.
    nonisolated static func unique(named name: String, in references: [ApplicationReference]) -> ApplicationReference? {
        let matches = references.filter { $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame }
        guard let first = matches.first, matches.allSatisfy({ $0.id == first.id }) else { return nil }
        return first
    }
}

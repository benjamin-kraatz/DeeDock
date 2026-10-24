import Foundation

/// One folder the scanner looks in, and how entries in it are named.
nonisolated struct AppLeftoverRoot: Sendable, Hashable {
    /// How entries in the folder relate to identifiers.
    enum Naming: Sendable, Hashable {
        /// Named after a bundle identifier, possibly with a suffix component and an extension
        /// (`com.example.App`, `com.example.App.ShipIt`, `com.example.App.plist`).
        case bundle
        /// Named exactly after an app group.
        case group
        /// Named after a bundle identifier or an app group (Application Scripts).
        case bundleOrGroup
        /// Launchd job files: `<identifier>.plist` or `<identifier>.<suffix>.plist`, for the app's and its
        /// helpers' identifiers.
        case launchd
        /// Privileged helper tools, named exactly after a helper identifier or prefixed by the app's.
        case helper
    }

    let url: URL
    let kind: AppLeftover.Kind
    let domain: AppLeftover.Domain
    let naming: Naming
    /// Whether an entry named exactly like the app also counts here, as a "Possibly related" match.
    let allowsNameMatches: Bool
}

/// Decides which entries of a folder belong to an app. Pure: it reads no files, so tests can pin the
/// rules down.
///
/// ## What is selected
/// An entry named exactly after one of the app's identifiers or app groups, or after an identifier plus
/// a suffix component that apps commonly add (`.ShipIt`, `.helper`, a ByHost UUID, …). These go in the
/// sheet's App data section, selected.
///
/// ## What is only offered
/// Any other `identifier.something` entry, and folders named exactly like the app (`Application
/// Support/Warp`), are ``AppLeftover/Match/similarName`` matches: listed under "Possibly related",
/// never selected by DOKK.
///
/// ## What is skipped or kept
/// - An entry that belongs to another installed app with a more specific identifier
///   (`com.example.App.Pro` while uninstalling `com.example.App`) is skipped.
/// - Data another installed app uses (the same app group, or another copy with the same bundle
///   identifier) is listed with ``AppLeftover/sharedWith`` set and starts unselected.
nonisolated struct AppLeftoverRules: Sendable {
    /// The app being uninstalled, as the rules see it.
    struct Identity: Sendable {
        /// The main bundle identifier first, then embedded bundles'.
        var identifiers: [String]
        var helperIdentifiers: [String]
        var appGroups: [String]
        var names: [String]
    }

    /// Another installed app, which may share or own similarly named data.
    struct OtherApp: Sendable {
        let bundleIdentifier: String?
        let name: String
        /// Every app group the app or its embedded bundles declare.
        let appGroups: [String]
        /// Identifiers of its embedded bundles and helpers. Filled for other copies of the app being
        /// uninstalled, whose extensions and helpers share the same data.
        var otherIdentifiers: [String] = []

        /// Whether this app uses data named after `identifier`.
        func uses(_ identifier: String) -> Bool {
            ([bundleIdentifier].compactMap { $0 } + otherIdentifiers).contains {
                $0.caseInsensitiveCompare(identifier) == .orderedSame
            }
        }
    }

    /// Suffix components apps add to their own identifier for helpers and updaters, compared in lowercase.
    static let ownSuffixes: Set<String> = [
        "shipit", "helper", "helpers", "loginhelper", "launcher", "agent", "launchagent", "daemon", "update",
        "updater", "updates", "autoupdate", "sparkle", "crashreporter", "crashpad", "plugin", "plugins",
        "extension", "xpc", "service", "widget",
    ]

    /// Extensions stripped from an entry before comparing it with identifiers.
    static let strippedExtensions = [".plist", ".savedState", ".binarycookies", ".lockfile"]

    /// Folder names too generic to count as a name match, compared in lowercase.
    static let genericNames: Set<String> = [
        "app", "apps", "application", "applications", "data", "cache", "caches", "logs", "log", "temp", "tmp",
        "support", "default", "shared", "common", "helper", "updater", "settings", "preferences", "library",
    ]

    let identity: Identity
    let others: [OtherApp]

    /// - Parameters:
    ///   - identity: The app being uninstalled. Identifiers with fewer than two components are dropped,
    ///     because they would match too broadly.
    ///   - others: The other installed apps, excluding every copy of this bundle at the same path.
    init(identity: Identity, others: [OtherApp]) {
        var identity = identity
        identity.identifiers = Self.unique(identity.identifiers.filter(Self.isSpecific))
        identity.helperIdentifiers = Self.unique(identity.helperIdentifiers.filter(Self.isSpecific))
        identity.appGroups = Self.unique(identity.appGroups.filter { !$0.isEmpty })
        identity.names = Self.unique(identity.names.filter {
            $0.count >= 3 && !Self.genericNames.contains($0.lowercased())
        })
        self.identity = identity
        self.others = others
    }

    /// The leftovers among `entries`, the names in `root`.
    func leftovers(in root: AppLeftoverRoot, entries: [String]) -> [AppLeftover] {
        entries.compactMap { entry in
            guard !entry.hasPrefix(".") || root.kind == .homeFolder else { return nil }
            return leftover(named: entry, in: root)
        }
    }

    private func leftover(named entry: String, in root: AppLeftoverRoot) -> AppLeftover? {
        let url = root.url.appendingPathComponent(entry)
        if root.kind == .homeFolder {
            let names = identity.names.map { "." + $0.lowercased().replacingOccurrences(of: " ", with: "") }
            guard names.contains(entry), !otherAppNamed(String(entry.dropFirst())) else { return nil }
            return AppLeftover(url: url, kind: .homeFolder, match: .similarName, domain: root.domain)
        }
        let stem = Self.stem(of: entry)
        switch root.naming {
        case .group:
            return groupLeftover(stem, url: url, root: root)
        case .bundleOrGroup:
            return groupLeftover(stem, url: url, root: root) ?? bundleLeftover(stem, url: url, root: root)
        case .bundle, .launchd:
            return bundleLeftover(stem, url: url, root: root)
        case .helper:
            if let helper = identity.helperIdentifiers.first(where: { $0.caseInsensitiveCompare(stem) == .orderedSame }) {
                return identifierLeftover(stem, identifier: helper, loose: false, url: url, root: root)
            }
            return bundleLeftover(stem, url: url, root: root)
        }
    }

    private func groupLeftover(_ stem: String, url: URL, root: AppLeftoverRoot) -> AppLeftover? {
        guard identity.appGroups.contains(stem) else { return nil }
        var item = AppLeftover(url: url, kind: root.kind == .scripts ? .scripts : .groupContainer,
                               match: .appGroup, domain: root.domain)
        item.sharedWith = others.first(where: { $0.appGroups.contains(stem) })?.name
        return item
    }

    private func bundleLeftover(_ stem: String, url: URL, root: AppLeftoverRoot) -> AppLeftover? {
        let candidates = root.naming == .launchd || root.naming == .helper
            ? identity.identifiers + identity.helperIdentifiers : identity.identifiers
        if let exact = candidates.first(where: { $0.caseInsensitiveCompare(stem) == .orderedSame }) {
            return identifierLeftover(stem, identifier: exact, loose: false, url: url, root: root)
        }
        // The longest identifier wins, so an embedded bundle's data isn't read as the app's.
        let prefixed = candidates.filter { stem.lowercased().hasPrefix($0.lowercased() + ".") }
        if let identifier = prefixed.max(by: { $0.count < $1.count }) {
            let suffix = String(stem.dropFirst(identifier.count + 1))
            return identifierLeftover(stem, identifier: identifier, loose: !Self.isOwnSuffix(suffix), url: url, root: root)
        }
        if root.allowsNameMatches, identity.names.contains(where: { $0.caseInsensitiveCompare(stem) == .orderedSame }),
           !otherAppNamed(stem) {
            return AppLeftover(url: url, kind: root.kind, match: .similarName, domain: root.domain)
        }
        return nil
    }

    private func identifierLeftover(_ stem: String, identifier: String, loose: Bool, url: URL,
                                    root: AppLeftoverRoot) -> AppLeftover? {
        // A more specific identifier of another installed app owns the entry.
        let owner = others.compactMap(\.bundleIdentifier).filter { other in
            other.count > identifier.count
                && (stem.caseInsensitiveCompare(other) == .orderedSame || stem.lowercased().hasPrefix(other.lowercased() + "."))
        }
        guard owner.isEmpty else { return nil }
        var kind = root.kind
        if kind == .container, let main = identity.identifiers.first, identifier != main { kind = .extensionContainer }
        var item = AppLeftover(url: url, kind: kind, match: loose ? .similarName : .bundleIdentifier, domain: root.domain)
        // Another copy of the app (or anything else declaring this identifier for a bundle or helper) uses it too.
        item.sharedWith = others.first(where: { $0.uses(identifier) })?.name
        return item
    }

    private func otherAppNamed(_ name: String) -> Bool {
        others.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// `entry` without the extensions apps use for per-app data files.
    static func stem(of entry: String) -> String {
        for suffix in strippedExtensions where entry.count > suffix.count && entry.lowercased().hasSuffix(suffix.lowercased()) {
            return String(entry.dropLast(suffix.count))
        }
        return entry
    }

    /// Whether `suffix`, the part after `identifier.`, is one apps add to their own identifier: a known
    /// helper or updater word, or a ByHost hardware UUID.
    static func isOwnSuffix(_ suffix: String) -> Bool {
        let first = suffix.split(separator: ".", maxSplits: 1).first.map(String.init) ?? suffix
        if ownSuffixes.contains(first.lowercased()) { return true }
        return UUID(uuidString: first) != nil || (first.count >= 12 && first.allSatisfy(\.isHexDigit))
    }

    /// At least two non-empty components, like `com.example`; a single word would match too broadly.
    static func isSpecific(_ identifier: String) -> Bool {
        identifier.split(separator: ".", omittingEmptySubsequences: false).filter { !$0.isEmpty }.count >= 2
            && !identifier.hasPrefix(".") && !identifier.hasSuffix(".")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

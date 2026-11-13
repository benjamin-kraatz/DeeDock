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
/// sheet's App data section, selected. An embedded bundle's identifier, a helper's, or an app group
/// counts only when it is related to the main bundle identifier; see ``owns(_:isGroup:)``.
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
        /// The main bundle identifier first (when ``hasMainIdentifier``), then embedded bundles'.
        var identifiers: [String]
        var helperIdentifiers: [String]
        var appGroups: [String]
        var names: [String]
        /// False when the app has no bundle identifier of its own, so `identifiers` holds only embedded
        /// bundles'. Nothing the app declares then counts as its own; see ``AppLeftoverRules/owns(_:isGroup:)``.
        var hasMainIdentifier = true
    }

    /// Another installed app, which may share or own similarly named data.
    struct OtherApp: Sendable {
        let bundleIdentifier: String?
        let name: String
        /// Every app group the app or its embedded bundles declare.
        let appGroups: [String]
        /// Identifiers of its embedded bundles and helpers. Other copies of the app being uninstalled fill
        /// both; other apps fill their helpers when the uninstalled app has helpers of its own.
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
    /// The app's own bundle identifier, which embedded, helper, and group identifiers must relate to.
    /// Nil when the app has none, or one too broad to keep.
    let mainIdentifier: String?

    /// - Parameters:
    ///   - identity: The app being uninstalled. Identifiers with fewer than two components are dropped,
    ///     because they would match too broadly.
    ///   - others: The other installed apps, excluding every copy of this bundle at the same path.
    init(identity: Identity, others: [OtherApp]) {
        var identity = identity
        // Taken before filtering: a dropped main identifier must not promote an embedded bundle's to main.
        let main = identity.hasMainIdentifier ? identity.identifiers.first : nil
        mainIdentifier = main.flatMap { Self.isSpecific($0) ? $0 : nil }
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
        let sharedWith = others.first(where: { $0.appGroups.contains(stem) })?.name
        // Shared data starts unselected anyway, and keeps its place in App data with its "Also used by" note.
        let match: AppLeftover.Match = sharedWith != nil || owns(stem, isGroup: true) ? .appGroup : .similarName
        var item = AppLeftover(url: url, kind: root.kind == .scripts ? .scripts : .groupContainer,
                               match: match, domain: root.domain)
        item.sharedWith = sharedWith
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
        // Another copy of the app (or anything else declaring this identifier for a bundle or helper) uses it too.
        let sharedWith = others.first(where: { $0.uses(identifier) })?.name
        // Shared data starts unselected anyway, and keeps its place in App data with its "Also used by" note.
        let trusted = sharedWith != nil || owns(identifier, isGroup: false)
        var item = AppLeftover(url: url, kind: kind, match: loose || !trusted ? .similarName : .bundleIdentifier,
                               domain: root.domain)
        item.sharedWith = sharedWith
        return item
    }

    /// Whether `identifier`, one the app declares for itself, is related to its main bundle identifier, so
    /// data named after it may be selected.
    ///
    /// Embedded bundles' identifiers, helper names, and app groups come from files inside the bundle that
    /// nothing verifies: unsigned `Info.plist`s, file names in `Contents/Library/LaunchDaemons` and its
    /// siblings, and entitlements read without validating the signature. Taken at face value, an app could
    /// declare another vendor's identifier and get that vendor's data selected; a LaunchDaemon moved to
    /// the Trash stops loading at the next restart. So such an identifier counts only when it:
    /// - is the main identifier or starts with `main.`; or
    /// - shares the main identifier's vendor prefix (see ``vendorPrefix(of:)``) and no other installed app
    ///   uses that prefix in its bundle identifier, helpers, or app groups. Other copies of this app don't
    ///   count. Team identifiers aren't compared: the rules don't receive other apps', and they come from
    ///   the same unvalidated signature.
    ///
    /// A `com.apple.` identifier never counts unless the main identifier is `com.apple.…` too, and without
    /// a main identifier nothing counts. Anything that fails is still listed, under "Possibly related".
    /// The main identifier itself always passes, so its own matches are unaffected.
    private func owns(_ identifier: String, isGroup: Bool) -> Bool {
        guard let main = mainIdentifier?.lowercased() else { return false }
        let value = Self.normalized(identifier, isGroup: isGroup)
        if value.hasPrefix("com.apple."), !main.hasPrefix("com.apple.") { return false }
        if value == main || value.hasPrefix(main + ".") { return true }
        guard let vendor = Self.vendorPrefix(of: value), vendor == Self.vendorPrefix(of: main) else { return false }
        return !others.contains { other in
            guard other.bundleIdentifier?.lowercased() != main else { return false }
            let theirs = ([other.bundleIdentifier].compactMap { $0 } + other.otherIdentifiers).map { Self.normalized($0, isGroup: false) }
                + other.appGroups.map { Self.normalized($0, isGroup: true) }
            return theirs.contains { Self.vendorPrefix(of: $0) == vendor }
        }
    }

    /// `identifier` in lowercase without a leading `group.` and, for an app group, without a leading team
    /// identifier (ten uppercase letters and digits, as in `ABCDE12345.com.example.shared`).
    static func normalized(_ identifier: String, isGroup: Bool) -> String {
        var value = Substring(identifier)
        if value.hasPrefix("group.") { value = value.dropFirst("group.".count) }
        if isGroup, let dot = value.firstIndex(of: "."), value.distance(from: value.startIndex, to: dot) == 10,
           value[..<dot].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
            value = value[value.index(after: dot)...]
        }
        return value.lowercased()
    }

    /// The first two components of a ``normalized(_:isGroup:)`` identifier (`com.example`), or nil when it
    /// has fewer than two.
    static func vendorPrefix(of normalized: String) -> String? {
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return "\(parts[0]).\(parts[1])"
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

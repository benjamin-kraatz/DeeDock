import Foundation

/// Why Vapor refused a dropped item. The view layer turns each case into its localized message
/// and the orb shakes red.
nonisolated enum VaporRefusal: Equatable, Sendable {
    /// A plain file or a symbolic link: "Vapor takes folders, not files."
    case notAFolder
    /// An app, framework or other bundle: "Vapor takes folders, not packages."
    case package
    /// The item, or a folder containing it, is already in the orb.
    case alreadyAdded(name: String)
    /// The home folder itself.
    case homeFolder
    /// Desktop, Documents, Downloads, Library and the other standard home folders.
    case standardFolder(name: String)
    /// `/System`, `/Library`, `/usr` and the other system locations, or anything inside them.
    case systemLocation(name: String)
    /// `/` or any volume's root folder.
    case volumeRoot(name: String)
    /// Nothing exists at the dropped path any more.
    case missing(name: String)
}

/// What a single dropped item turns out to be on disk.
nonisolated enum VaporItemKind: Equatable, Sendable {
    case folder, file, package, symbolicLink, missing
}

/// The outcome of evaluating one dropped item against the folders already in the orb.
nonisolated enum VaporDropDecision: Equatable, Sendable {
    /// Add `url`, and take out the folders in `replacing`, which it contains.
    case accept(url: URL, replacing: [URL])
    case refuse(VaporRefusal)
}

/// File-system questions the drop policy asks. Tests supply fixed answers for fake paths.
nonisolated struct VaporFileInspector: Sendable {
    var kind: @Sendable (URL) -> VaporItemKind
    var isVolumeRoot: @Sendable (URL) -> Bool
    /// The path with symbolic links in its parent folders resolved (the last component is kept,
    /// since `kind` already refuses a final link). Fake inspectors leave paths as they are.
    var resolve: @Sendable (URL) -> URL = { $0 }

    /// Reads resource values without following a final symbolic link.
    static let live = VaporFileInspector(
        kind: { url in
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
            guard let values = try? url.resourceValues(forKeys: keys) else { return .missing }
            if values.isSymbolicLink == true { return .symbolicLink }
            if values.isPackage == true { return .package }
            return values.isDirectory == true ? .folder : .file
        },
        isVolumeRoot: { url in
            (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
        },
        // `realpath` rather than `resolvingSymlinksInPath`: it keeps the `/private` prefix, so
        // `/var/…` resolves to the protected `/private/var/…` instead of losing it.
        resolve: { url in
            let parent = url.deletingLastPathComponent()
            guard let real = realpath(parent.path, nil) else { return url }
            defer { free(real) }
            return URL(fileURLWithPath: String(cString: real), isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
        }
    )
}

/// Decides which dropped items Vapor accepts. Pure apart from the injected inspector.
///
/// Paths compare lexically and without case (the default APFS rule), after `..` is collapsed.
/// Symbolic links are refused as files: renaming one would only move the link.
nonisolated struct VaporDropPolicy: Sendable {
    /// System locations protected with everything inside them.
    /// `/tmp` is not in the spec's list but is a link to `/private/tmp`, which is.
    static let systemRoots = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private",
                              "/etc", "/var", "/opt", "/cores", "/tmp"]
    /// Protected as folders themselves, not their contents. `/Users` and `/Volumes` are additions
    /// to the spec's list: one holds every home folder, the other every mounted disk.
    static let exactRoots = ["/", "/Users", "/Volumes"]
    /// Standard folders directly inside the home folder. Their subfolders are allowed.
    static let standardHomeFolders = ["Desktop", "Documents", "Downloads", "Library", "Applications", "Movies",
                                      "Music", "Pictures", "Public"]

    let home: URL
    var systemRoots: [String] = VaporDropPolicy.systemRoots
    /// Vapor's own staging folders. Dropping one, or anything in it, is refused like a system location.
    var stagingRoots: [URL] = []
    var inspector: VaporFileInspector = .live

    /// Evaluates one dropped item against `existing`, the folders already in the orb.
    func evaluate(_ dropped: URL, existing: [URL]) -> VaporDropDecision {
        let url = Self.normalized(dropped)
        let name = Self.displayName(url)
        if let refusal = protectedRefusal(url, name: name, home: Self.normalized(home)) { return .refuse(refusal) }
        // A linked parent folder can lead somewhere protected: with `~/alias` pointing at the home
        // folder, `~/alias/Documents` is the real Documents. Check the resolved path too.
        let resolved = Self.normalized(inspector.resolve(url))
        if resolved.path != url.path,
           let refusal = protectedRefusal(resolved, name: name, home: Self.normalized(inspector.resolve(home))) {
            return .refuse(refusal)
        }
        switch inspector.kind(url) {
        case .missing: return .refuse(.missing(name: name))
        case .file, .symbolicLink: return .refuse(.notAFolder)
        case .package: return .refuse(.package)
        case .folder: break
        }
        if inspector.isVolumeRoot(url) { return .refuse(.volumeRoot(name: name)) }
        let normalizedExisting = existing.map(Self.normalized)
        if normalizedExisting.contains(where: { url.isSameOrDescendant(of: $0, resolvingSymlinks: false) }) {
            return .refuse(.alreadyAdded(name: name))
        }
        let replaced = zip(existing, normalizedExisting)
            .filter { $0.1.isSameOrDescendant(of: url, resolvingSymlinks: false) }
            .map(\.0)
        return .accept(url: url, replacing: replaced)
    }

    /// Evaluates several items dropped at once, in order. Each accepted folder counts as existing
    /// for the items after it, so a parent and its child in one drop keep only the parent.
    func evaluate(_ dropped: [URL], existing: [URL]) -> [VaporDropDecision] {
        var current = existing
        return dropped.map { url in
            let decision = evaluate(url, existing: current)
            if case .accept(let accepted, let replacing) = decision {
                current.removeAll { replaced in replacing.contains(replaced) }
                current.append(accepted)
            }
            return decision
        }
    }

    /// Checks a folder already in the orb again, right before it is deleted. Between Add and
    /// Delete it may have been swapped for a symbolic link or moved under a protected location.
    /// - Returns: The refusal, or nil when the folder may still be deleted.
    func revalidate(_ url: URL) -> VaporRefusal? {
        switch evaluate(url, existing: []) {
        case .accept: nil
        case .refuse(let refusal): refusal
        }
    }

    private func protectedRefusal(_ url: URL, name: String, home homeURL: URL) -> VaporRefusal? {
        let path = url.path
        if path == "/" { return .volumeRoot(name: name) }
        if Self.same(url, homeURL) { return .homeFolder }
        if Self.same(url.deletingLastPathComponent(), homeURL),
           Self.standardHomeFolders.contains(where: { $0.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame }) {
            return .standardFolder(name: name)
        }
        if Self.exactRoots.contains(where: { Self.same(url, URL(fileURLWithPath: $0)) }) {
            return .systemLocation(name: name)
        }
        for root in systemRoots where url.isSameOrDescendant(of: URL(fileURLWithPath: root), resolvingSymlinks: false) {
            return .systemLocation(name: name)
        }
        for root in stagingRoots where url.isSameOrDescendant(of: root, resolvingSymlinks: false) {
            return .systemLocation(name: name)
        }
        if url.lastPathComponent.hasSuffix(".dokk-vapor") || url.lastPathComponent.contains(".dokk-vapor-") {
            return .systemLocation(name: name)
        }
        return nil
    }

    private static func same(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.isSameOrDescendant(of: rhs, resolvingSymlinks: false) && rhs.isSameOrDescendant(of: lhs, resolvingSymlinks: false)
    }

    /// Collapses `.`/`..` and a trailing slash without touching the file system. Unlike
    /// `standardizedFileURL`, it keeps a `/private` prefix, so `/private/var/…` stays protected.
    static func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardized.path)
    }

    /// The name shown in a refusal: the folder's name, or the path for `/`.
    private static func displayName(_ url: URL) -> String {
        url.path == "/" ? "/" : url.lastPathComponent
    }
}

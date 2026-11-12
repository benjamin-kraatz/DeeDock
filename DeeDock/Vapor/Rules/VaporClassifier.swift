import Foundation

/// Recognizes cache and build folders by name and by sibling marker files only. It never reads
/// a folder's contents, so it is cheap enough to run for every child of a Finder folder.
///
/// The rules are the table in `docs/VAPOR.md`. Names compare exactly (case-sensitive), as the
/// tools that create these folders spell them.
nonisolated enum VaporClassifier {
    /// Names that are recognized on their own, without a marker file.
    private static let names: [String: VaporTag] = [
        "node_modules": .npmPackages,
        ".next": .nextBuild,
        ".nuxt": .nuxtBuild,
        ".svelte-kit": .svelteKitBuild,
        ".turbo": .turborepoCache,
        ".parcel-cache": .parcelCache,
        "coverage": .testCoverage,
        "DerivedData": .xcodeBuildCache,
        "ModuleCache.noindex": .xcodeModuleCache,
        ".gradle": .gradleCache,
        "__pycache__": .pythonCache,
        ".pytest_cache": .pythonCache,
        ".mypy_cache": .pythonCache,
        ".ruff_cache": .pythonCache,
        "dist": .buildOutput,
        "build": .buildOutput,
        "out": .buildOutput,
    ]

    /// Names that count only when the parent folder holds a marker file.
    private static let markedNames: [String: (marker: String, tag: VaporTag)] = [
        ".build": ("Package.swift", .swiftPMBuild),
        "target": ("Cargo.toml", .cargoBuild),
        "Pods": ("Podfile", .cocoaPods),
    ]

    /// The tag for `url`, or nil when no rule matches.
    ///
    /// - Parameters:
    ///   - url: A folder. Its existence is not checked.
    ///   - home: The home folder, for the `~/Library/Caches/org.swift.swiftpm` rule.
    ///   - fileExists: Reports whether a sibling marker exists. Defaults to the file system.
    static func tag(for url: URL, home: URL,
                    fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> VaporTag? {
        let name = url.lastPathComponent
        if let tag = names[name] { return tag }
        let parent = url.deletingLastPathComponent()
        if let rule = markedNames[name], fileExists(parent.appendingPathComponent(rule.marker)) { return rule.tag }
        // A direct child of a DerivedData folder is one project's build data, named "App-abcdef…".
        if parent.lastPathComponent == "DerivedData" { return .xcodeBuildData }
        let swiftPMCache = home.appendingPathComponent("Library/Caches/org.swift.swiftpm")
        if url.isSameOrDescendant(of: swiftPMCache, resolvingSymlinks: false) { return .swiftPMCache }
        return nil
    }

    /// The classification shown in the orb and the panel.
    static func classify(_ url: URL, home: URL,
                         fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> VaporClassification {
        tag(for: url, home: home, fileExists: fileExists).map(VaporClassification.known) ?? .unknown
    }
}

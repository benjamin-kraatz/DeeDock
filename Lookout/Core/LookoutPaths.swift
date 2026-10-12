import Foundation

/// Where Lookout keeps its data: one folder holding the index (`index.sqlite` and its WAL), the downloaded models,
/// model downloads in progress and the services' logs. The real one is in `~/Library/Application Support/DDock/`,
/// beside DOKK's other Application Support data, one per app identity (`standard`); tests and the bench pass a base of
/// their own.
///
/// The folder is inside `~/Library`, which the crawler never walks (`Rules.skipReason`), so the index can't index
/// itself. Nothing is created until a caller asks for a folder with `create`.
nonisolated struct LookoutPaths: Sendable, Equatable {
    /// The folder everything else is in.
    let base: URL

    init(base: URL) {
        self.base = base
    }

    /// The release app's bundle identifier. Its data keeps the original folder, `DDock/Lookout/`.
    static let releaseIdentifier = "de.benjaminkraatz.DeeDock"
    /// The services' bundle identifiers are the app's plus one of these (`LookoutServiceNames`).
    static let serviceSuffixes = [".LookoutIndexService", ".LookoutQueryService"]

    /// This process's folder: the app's, or for a service, the folder of the app that embeds it, so the app and its
    /// services always agree (`appIdentifier(fromBundleIdentifier:)`).
    static let standard = standard(forBundleIdentifier: Bundle.main.bundleIdentifier)

    /// The folder of the app identity `bundleIdentifier` belongs to, in `~/Library/Application Support/DDock/`.
    ///
    /// Each identity has its own: the Debug app (`….DeeDock.dev`) and the Release app have their own settings and
    /// their own services, and with one shared index either service would prune the other's folders, and deleting in
    /// one would unlink files the other is writing. So a development build downloads its own copy of the model.
    /// A process without an identifier (a command-line tool) gets the release folder.
    static func standard(forBundleIdentifier bundleIdentifier: String?,
                         applicationSupport: URL = .applicationSupportDirectory) -> LookoutPaths {
        let name = folderName(forApp: appIdentifier(fromBundleIdentifier: bundleIdentifier ?? releaseIdentifier))
        return LookoutPaths(base: applicationSupport.appending(path: "DDock/" + name, directoryHint: .isDirectory))
    }

    /// The app identity a bundle identifier belongs to: a service's identifier without its suffix, an app's as it is.
    static func appIdentifier(fromBundleIdentifier identifier: String) -> String {
        guard let suffix = serviceSuffixes.first(where: { identifier.hasSuffix($0) && identifier.count > $0.count })
        else { return identifier }
        return String(identifier.dropLast(suffix.count))
    }

    /// `Lookout` for the release identity; `Lookout-<suffix>` for one that extends it (`Lookout-dev` for
    /// `….DeeDock.dev`), and `Lookout-<identifier>` for any other. Characters other than letters, digits, `-` and `_`
    /// become `-`, so the name is one plain path component.
    static func folderName(forApp identifier: String) -> String {
        guard identifier != releaseIdentifier else { return "Lookout" }
        let suffix = identifier.hasPrefix(releaseIdentifier + ".")
            ? String(identifier.dropFirst(releaseIdentifier.count + 1)) : identifier
        let safe = String(suffix.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "-"
        })
        return "Lookout-" + (safe.isEmpty ? "unknown" : safe)
    }

    /// The folder `index.sqlite` lives in (the base itself: `IndexStore` takes a folder and a file name).
    var index: URL { base }
    /// The index database. Its `-wal` and `-shm` files sit beside it.
    var indexFile: URL { base.appending(path: IndexStore.mainFile, directoryHint: .notDirectory) }
    /// The model files (`ModelFiles`).
    var models: URL { base.appending(path: "Models", directoryHint: .isDirectory) }
    /// Model downloads in progress (the app's `LookoutModelDownloader`). A file moves into `models` only once its
    /// checksum matches, so the services never see a partial one.
    var partialDownloads: URL { base.appending(path: "Partial", directoryHint: .isDirectory) }
    /// The index database and the files SQLite keeps beside it (write-ahead log, shared memory, rollback journal).
    var indexFiles: [URL] {
        ["", "-wal", "-shm", "-journal"].map { base.appending(path: IndexStore.mainFile + $0, directoryHint: .notDirectory) }
    }
    /// The services' logs: llama.cpp's warnings and errors (`LlamaLog`).
    var logs: URL { base.appending(path: "Logs", directoryHint: .isDirectory) }

    /// A log file in `logs`, creating the folder first.
    ///
    /// - Throws: The folder can't be created.
    func logFile(_ name: String) throws -> URL {
        try Self.create(logs).appending(path: name, directoryHint: .notDirectory)
    }

    /// Creates `folder` (and its parents) when it isn't there yet, and returns it.
    ///
    /// - Throws: The folder can't be created.
    @discardableResult
    static func create(_ folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

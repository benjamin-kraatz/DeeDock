import Foundation

/// Where Lookout keeps its data: one folder holding the index (`index.sqlite` and its WAL), the downloaded models and
/// the services' logs. The real one is `~/Library/Application Support/DDock/Lookout/`, beside DOKK's other
/// Application Support data; tests and the bench pass a base of their own.
///
/// The folder is inside `~/Library`, which the crawler never walks (`Rules.skipReason`), so the index can't index
/// itself. Nothing is created until a caller asks for a folder with `create`.
nonisolated struct LookoutPaths: Sendable, Equatable {
    /// The folder everything else is in.
    let base: URL

    init(base: URL) {
        self.base = base
    }

    /// `~/Library/Application Support/DDock/Lookout/`. Debug and release builds share it, so a development build
    /// needn't download the models again.
    static let standard = LookoutPaths(base: URL.applicationSupportDirectory
        .appending(path: "DDock/Lookout", directoryHint: .isDirectory))

    /// The folder `index.sqlite` lives in (the base itself: `IndexStore` takes a folder and a file name).
    var index: URL { base }
    /// The index database. Its `-wal` and `-shm` files sit beside it.
    var indexFile: URL { base.appending(path: IndexStore.mainFile, directoryHint: .notDirectory) }
    /// The model files (`ModelFiles`).
    var models: URL { base.appending(path: "Models", directoryHint: .isDirectory) }
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

import Foundation
@testable import DeeDock

/// A fresh folder under the temporary directory, removed when the test that made it is done. Its `url` is the real
/// path (`/private/var/…`), the way Lookout's crawl reports files.
final class LookoutTestFolder {
    let url: URL

    init() {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("LookoutTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        url = URL(fileURLWithPath: FolderSelection.realPath(made.path), isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var path: String { url.path }

    /// Writes `contents` at `relative` (creating its folders) and returns its URL.
    @discardableResult
    func write(_ relative: String, _ contents: Data = Data("text".utf8)) throws -> URL {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file)
        return file
    }

    /// Creates the folder at `relative` and returns its URL.
    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let folder = url.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

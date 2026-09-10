import Foundation

/// Stores the collection as one JSON file, PNG files, and encrypted vault files under
/// `Application Support/<bundle identifier>/ClipboardMuseum`.
///
/// Clipboard content is too large and too personal for UserDefaults. The folder is created
/// owner-only (0700), files are 0600, and the folder is excluded from backups. Nothing here syncs.
nonisolated struct ClipboardMuseumRepository: Sendable {
    let directory: URL

    init(directory: URL = ClipboardMuseumRepository.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DeeDock", isDirectory: true)
            .appendingPathComponent("ClipboardMuseum", isDirectory: true)
    }

    var documentURL: URL { directory.appendingPathComponent("collection.json") }
    private var imagesURL: URL { directory.appendingPathComponent("Images", isDirectory: true) }
    private var vaultURL: URL { directory.appendingPathComponent("Vault", isDirectory: true) }

    /// Only names this repository generates are accepted, so a tampered document cannot point
    /// deletion or reads outside its folders.
    static func isImageName(_ name: String) -> Bool { isGenerated(name, suffix: ".png") }
    static func isSealedName(_ name: String) -> Bool { isGenerated(name, suffix: ".sealed") }

    private static func isGenerated(_ name: String, suffix: String) -> Bool {
        name.hasSuffix(suffix) && UUID(uuidString: String(name.dropLast(suffix.count))) != nil
    }

    /// Returns nil when nothing has been stored yet. Throws for unreadable or oversized files so
    /// they are not mistaken for an empty collection and overwritten.
    func load() throws -> ClipboardMuseumDocument? {
        guard FileManager.default.fileExists(atPath: documentURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: documentURL.path)
        guard let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= ClipboardMuseumLimits.maximumDocumentBytes else { throw CocoaError(.coderReadCorrupt) }
        let document = try JSONDecoder().decode(ClipboardMuseumDocument.self, from: Data(contentsOf: documentURL))
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    func save(_ document: ClipboardMuseumDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        let data = try JSONEncoder().encode(document)
        guard data.count <= ClipboardMuseumLimits.maximumDocumentBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try prepareDirectory()
        try data.write(to: documentURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: documentURL.path)
    }

    /// Writes a new PNG and returns its generated file name.
    func writeImage(_ data: Data) throws -> String {
        try write(data, into: imagesURL, suffix: ".png")
    }

    func imageURL(named name: String) -> URL? {
        Self.isImageName(name) ? imagesURL.appendingPathComponent(name) : nil
    }

    func removeImage(named name: String) {
        guard let url = imageURL(named: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes an already encrypted blob and returns its generated file name.
    func writeSealed(_ data: Data) throws -> String {
        try write(data, into: vaultURL, suffix: ".sealed")
    }

    func readSealed(named name: String) throws -> Data {
        guard Self.isSealedName(name) else { throw CocoaError(.fileReadInvalidFileName) }
        return try Data(contentsOf: vaultURL.appendingPathComponent(name))
    }

    func removeSealed(named name: String) {
        guard Self.isSealedName(name) else { return }
        try? FileManager.default.removeItem(at: vaultURL.appendingPathComponent(name))
    }

    /// Deletes files no exhibit references, such as one written just before a crash.
    func prune(keepingImages images: Set<String>, sealed: Set<String>) {
        let manager = FileManager.default
        for name in (try? manager.contentsOfDirectory(atPath: imagesURL.path)) ?? []
        where Self.isImageName(name) && !images.contains(name) {
            removeImage(named: name)
        }
        for name in (try? manager.contentsOfDirectory(atPath: vaultURL.path)) ?? []
        where Self.isSealedName(name) && !sealed.contains(name) {
            removeSealed(named: name)
        }
    }

    /// Removes the whole folder, including any unreadable collection file.
    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func write(_ data: Data, into folder: URL, suffix: String) throws -> String {
        try prepareDirectory()
        let name = UUID().uuidString + suffix
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .withoutOverwriting)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return name
    }

    private func prepareDirectory() throws {
        for folder in [imagesURL, vaultURL] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = directory
        try? folder.setResourceValues(values)
    }
}

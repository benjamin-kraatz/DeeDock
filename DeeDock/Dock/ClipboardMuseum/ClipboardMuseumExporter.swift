import AppKit
import UniformTypeIdentifiers

/// Save to Files choices, offered per medium.
enum ClipboardExportFormat: String, CaseIterable, Identifiable {
    case plainText, markdown, image, files

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .plainText: .clipboardMuseumSaveText
        case .markdown: .clipboardMuseumSaveMarkdown
        case .image: .clipboardMuseumSaveImage
        case .files: .clipboardMuseumSaveFiles
        }
    }

    static func formats(for kind: ClipboardExhibitKind) -> [ClipboardExportFormat] {
        switch kind {
        case .text, .link: [.plainText, .markdown]
        case .image: [.image]
        case .files: [.files, .markdown]
        }
    }
}

/// Markdown rendering of an exhibit: a heading, a catalog line, the content, and wall text.
nonisolated enum ClipboardMuseumMarkdown {
    static func document(for exhibit: ClipboardExhibit, text: String?, title: String, catalogLine: String) -> String {
        var parts = ["# " + title, "> " + catalogLine]
        if let note = exhibit.curatorNote { parts.append("_" + note + "_") }
        switch exhibit.kind {
        case .text:
            parts.append(text ?? "")
        case .link:
            if let text, let url = URL(string: text) {
                parts.append("[\(url.host() ?? text)](\(text))")
            }
        case .files:
            let paths = (text ?? "").split(separator: "\n")
            parts.append(paths.map { "- `\($0)`" }.joined(separator: "\n"))
        case .image:
            if let recognized = exhibit.recognizedText { parts.append(recognized) }
        }
        return parts.joined(separator: "\n\n") + "\n"
    }
}

/// Writes exhibits through the native save and folder panels. Nothing is written without a panel.
@MainActor
enum ClipboardMuseumExporter {
    /// - Parameters:
    ///   - text: The text to write, which is the revealed text for a redacted exhibit.
    ///   - imageData: PNG bytes for image exports.
    ///   - completion: Called with false when writing failed; not called on cancel.
    static func save(_ exhibit: ClipboardExhibit, as format: ClipboardExportFormat, text: String?,
                     imageData: Data?, completion: @escaping @MainActor (Bool) -> Void) {
        let name = fileName(exhibit.plainTitle)
        switch format {
        case .plainText:
            guard let text else { return completion(false) }
            present(data: Data(text.utf8), name: name, type: .plainText, completion: completion)
        case .markdown:
            let catalog = [String(localized: .clipboardMuseumCatalogNumber(exhibit.catalogNumber)),
                           String(localized: exhibit.medium),
                           exhibit.acquiredAt.formatted(date: .abbreviated, time: .shortened),
                           exhibit.sourceName].compactMap(\.self).joined(separator: " · ")
            let markdown = ClipboardMuseumMarkdown.document(for: exhibit, text: text, title: exhibit.plainTitle,
                                                            catalogLine: catalog)
            let type = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
            present(data: Data(markdown.utf8), name: name, type: type, completion: completion)
        case .image:
            guard let imageData else { return completion(false) }
            present(data: imageData, name: name, type: .png, completion: completion)
        case .files:
            copyFiles(exhibit.fileURLs, completion: completion)
        }
    }

    private static func present(data: Data, name: String, type: UTType, completion: @escaping @MainActor (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let written = (try? data.write(to: url, options: .atomic)) != nil
            MainActor.assumeIsolated { completion(written) }
        }
    }

    /// Copies each existing file into a chosen folder. A name collision gets a numbered suffix
    /// instead of replacing the file already there.
    private static func copyFiles(_ urls: [URL], completion: @escaping @MainActor (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: .clipboardMuseumSaveFilesPrompt)
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            var succeeded = true
            for url in urls {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                var target = folder.appendingPathComponent(url.lastPathComponent)
                var counter = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
                    counter += 1
                }
                if (try? FileManager.default.copyItem(at: url, to: target)) == nil { succeeded = false }
            }
            MainActor.assumeIsolated { completion(succeeded) }
        }
    }

    private static func fileName(_ title: String) -> String {
        let cleaned = title.map { "/:\\\n\r".contains($0) ? "-" : $0 }
        let name = String(String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return name.isEmpty ? String(localized: .clipboardMuseumTitle) : name
    }
}

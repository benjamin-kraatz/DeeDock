import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Encodes a finished markup and hands it to the clipboard, a file, or another app.
///
/// Nothing here decides *whether* to write: the session does that on an explicit action. Copy is
/// always PNG plus TIFF so both modern and older paste targets accept it.
nonisolated enum WindowMarkupExport {
    /// Encoded bytes in `format`. JPEG flattens transparency onto white and uses a high quality.
    static func data(_ image: CGImage, format: WindowMarkupFormat) -> Data? {
        let type: UTType = format == .png ? .png : .jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A file name from the window title and the moment, safe for the save panel.
    ///
    /// Separators and colons become spaces rather than vanishing, so two titles that differ only
    /// by punctuation still produce different names.
    static func suggestedFilename(title: String, appName: String, at date: Date, format: WindowMarkupFormat) -> String {
        let source = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appName : title
        let stripped = source.unicodeScalars.map { scalar -> Character in
            CharacterSet.newlines.contains(scalar) || scalar == "/" || scalar == ":" ? " " : Character(scalar)
        }
        let collapsed = String(stripped).split(separator: " ").joined(separator: " ")
        let name = collapsed.isEmpty ? "Markup" : String(collapsed.prefix(80))
        return "\(name) \(timestamp.string(from: date)).\(format.fileExtension)"
    }

    /// A destination inside `folder` that does not exist yet; a collision gets a numbered suffix.
    static func uniqueURL(in folder: URL, filename: String, fileManager: FileManager = .default) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    /// Fixed field order, no locale, so names sort by time everywhere.
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}

@MainActor
extension WindowMarkupExport {
    /// Puts the picture on the general pasteboard as PNG and TIFF.
    static func copy(_ image: CGImage) -> Bool {
        guard let png = data(image, format: .png) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let tiff = bitmap.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }

    /// An item provider for dragging the picture out: PNG data for apps, a file for Finder.
    ///
    /// The file representation writes to a temporary directory only when a drop target asks for a
    /// file, so a drag that ends in a text field or is cancelled never touches the disk.
    static func dragProvider(png: Data, filename: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = filename
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(png, nil)
            return nil
        }
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [],
                                            visibility: .all) { completion in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeeDockMarkup-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(filename)
                try png.write(to: url, options: .atomic)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }
}

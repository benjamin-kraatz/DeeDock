import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Reads image, PDF, and audiovisual headers away from the main actor.
///
/// Failures return `nil`. Cloud-only placeholders are skipped so opening a stack never starts a download.
nonisolated enum FolderStackMediaReader {
    /// True when the listing type can expose dimensions, a page count, or a duration.
    static func isCandidate(_ reference: FolderStackEntryReference) -> Bool {
        kind(of: reference) != nil
    }

    /// iCloud items that are not already local stay unread.
    static func hasLocalContents(
        isUbiquitous: Bool?,
        status: URLUbiquitousItemDownloadingStatus?
    ) -> Bool {
        guard isUbiquitous == true else { return true }
        return status == .current || status == .downloaded
    }

    /// Reads ubiquity keys from `url`. Missing keys count as local.
    static func hasLocalContents(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ])
        return hasLocalContents(isUbiquitous: values?.isUbiquitousItem,
                                status: values?.ubiquitousItemDownloadingStatus)
    }

    /// Holds `access` for the whole batch so the folder bookmark outlives navigation of individual files.
    static func load(_ references: [FolderStackEntryReference],
                     cache: FolderStackMediaCache,
                     access: FolderResourceAccess) async -> [String: FolderStackMediaMetadata] {
        _ = access.url
        var results: [String: FolderStackMediaMetadata] = [:]
        for reference in references {
            if Task.isCancelled { break }
            do { try Task.checkCancellation() } catch { break }
            let key = FolderStackMediaCacheKey(reference)
            if let cached = await cache.value(for: key) {
                if case .metadata(let media) = cached { results[reference.id] = media }
                continue
            }
            guard hasLocalContents(reference.url) else { continue }
            let media = await metadata(for: reference)
            if Task.isCancelled { break }
            await cache.store(media.map(FolderStackMediaCacheValue.metadata) ?? .unavailable, for: key)
            if let media { results[reference.id] = media }
        }
        return results
    }

    /// Returns typed headers or `nil` when the file is a folder, cloud-only, cancelled, or unreadable.
    static func metadata(for reference: FolderStackEntryReference) async -> FolderStackMediaMetadata? {
        guard !reference.isFolder, hasLocalContents(reference.url) else { return nil }
        if Task.isCancelled { return nil }
        switch kind(of: reference) {
        case .image: return imageMetadata(at: reference.url)
        case .pdf: return pdfMetadata(at: reference.url)
        case .audio: return await audiovisualMetadata(at: reference.url, video: false)
        case .video: return await audiovisualMetadata(at: reference.url, video: true)
        case nil: return nil
        }
    }

    private enum Kind { case image, pdf, audio, video }

    private static func kind(of reference: FolderStackEntryReference) -> Kind? {
        guard !reference.isFolder else { return nil }
        let type = reference.contentType.flatMap(UTType.init)
            ?? UTType(filenameExtension: reference.url.pathExtension)
        guard let type else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .audiovisualContent) { return .video }
        return nil
    }

    private static func imageMetadata(at url: URL) -> FolderStackMediaMetadata? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = integer(properties[kCGImagePropertyPixelWidth]),
              let height = integer(properties[kCGImagePropertyPixelHeight]),
              width > 0, height > 0
        else { return nil }
        let orientation = integer(properties[kCGImagePropertyOrientation])
        let size = orientedSize(width: width, height: height, orientation: orientation)
        return .image(width: size.width, height: size.height)
    }

    private static func pdfMetadata(at url: URL) -> FolderStackMediaMetadata? {
        guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
        let count = document.pageCount
        guard count > 0 else { return nil }
        return .pdf(pageCount: count)
    }

    private static func audiovisualMetadata(at url: URL, video: Bool) async -> FolderStackMediaMetadata? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        do {
            let duration = try await asset.load(.duration)
            guard duration.isNumeric, !duration.isIndefinite else { return nil }
            let seconds = duration.seconds
            guard seconds.isFinite, seconds >= 0 else { return nil }
            return video ? .video(duration: seconds) : .audio(duration: seconds)
        } catch {
            return nil
        }
    }

    /// TIFF orientations 5...8 display with swapped pixel axes.
    private static func orientedSize(width: Int, height: Int, orientation: Int?) -> (width: Int, height: Int) {
        switch orientation {
        case 5, 6, 7, 8: (height, width)
        default: (width, height)
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

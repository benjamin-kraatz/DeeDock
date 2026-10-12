import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import DeeDock

/// A query encoder that reads pictures: cold until its picture reader is woken, then warm, with a chosen delay per
/// call. Every picture's vector is `vector`.
@MainActor final class FakePictureEncoder: LookoutQueryEncoding {
    var isWarm = true
    private(set) var isPictureReaderWarm = false
    var delay: Duration = .zero
    var fails = false
    var vector = LookoutSearchIndex.query
    private(set) var pictureWarmUps = 0
    private(set) var pictures: [QueryPicture] = []

    func warmUp() async throws {}
    func embed(query: String) async throws -> [Float] { LookoutSearchIndex.query }
    func invalidate() {}

    func warmUpPictureReader() async throws {
        pictureWarmUps += 1
        try await Task.sleep(for: delay)
        if fails { throw LookoutEncoderError.service("no media file") }
        isPictureReaderWarm = true
    }

    func embed(picture: QueryPicture) async throws -> [Float] {
        pictures.append(picture)
        try await Task.sleep(for: delay)
        if fails { throw LookoutEncoderError.service("no media file") }
        isPictureReaderWarm = true
        return vector
    }
}

/// An index reader for searches with a vector: it records the requests and answers with `results`, and knows the
/// stored vectors in `sources` by path.
actor FakePictureReader: LookoutIndexSearching {
    private(set) var requests: [LookoutSimilarRequest] = []
    private(set) var sourceLookups: [(path: String, segmentID: Int64?)] = []
    private var sources: [String: LookoutSimilarSource] = [:]
    private var results: LookoutSimilarResults?
    private var delay: Duration = .zero

    func setSource(_ source: LookoutSimilarSource) { sources[source.path] = source }
    func setResults(_ results: LookoutSimilarResults?) { self.results = results }
    func setDelay(_ delay: Duration) { self.delay = delay }

    func search(_ request: LookoutSearchRequest) async throws -> LookoutResultSet? { nil }
    func prepareVectors() {}
    func releaseVectors() {}
    func indexDidChange() {}
    func closeIndex() {}
    func searchableFileCounts(under folders: [String]) -> [String: Int] { [:] }

    /// Answers as the index was when it was asked, like a query against the database, however long it then takes.
    func similar(_ request: LookoutSimilarRequest) async throws -> LookoutSimilarResults? {
        requests.append(request)
        let answer = results
        try? await Task.sleep(for: delay)
        return answer.map { LookoutSimilarResults(queryIsPicture: request.queryIsPicture, groups: $0.groups) }
    }

    func similarSource(path: String, segmentID: Int64?) -> LookoutSimilarSource? {
        sourceLookups.append((path, segmentID))
        return sources[path]
    }

    func indexedPaths(_ paths: [String]) -> Set<String> { Set(paths.filter { sources[$0] != nil }) }
}

/// Pictures made in memory for tests: a gradient, encoded as PNG.
enum LookoutTestPictures {
    /// PNG bytes of a `width` × `height` gradient.
    static func png(width: Int = 320, height: Int = 240) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
                                                               CGColor(red: 0.9, green: 0.8, blue: 0.4, alpha: 1)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A PNG file in `folder`.
    static func file(named name: String, in folder: LookoutTestFolder) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        try png().write(to: url)
        return url
    }
}

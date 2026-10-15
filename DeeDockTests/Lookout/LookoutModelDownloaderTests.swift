import CryptoKit
import Foundation
import Testing
@testable import DeeDock

/// `LookoutModelDownloader` against a fake Hugging Face (`LookoutFakeModelServer`) and tiny fake files: a file gets
/// its final name only once its checksum matches, a mismatch is rejected, an interrupted file resumes with a range
/// request, and a full disk stops the download before it starts. Nothing here reaches the network.
@MainActor
@Suite(.serialized)
struct LookoutModelDownloaderTests {
    private let base: URL
    private let paths: LookoutPaths

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appending(path: "LookoutDownloaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = LookoutPaths(base: base)
    }

    private func fakeFile(_ body: Data, sha: String? = nil) -> ModelFiles.File {
        let name = "lookout-test-\(UUID().uuidString).gguf"
        return ModelFiles.File(name: name, bytes: Int64(body.count),
                               sha256: sha ?? SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
    }

    private func downloader(_ files: [ModelFiles.File], freeSpace: Int64 = 10 << 30) -> LookoutModelDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LookoutFakeModelServer.self]
        return LookoutModelDownloader(paths: paths, files: files, configuration: configuration,
                                      availableSpace: { _ in freeSpace }, canDownload: true)
    }

    private func body(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    }

    private func finished(_ downloader: LookoutModelDownloader) async -> Bool {
        await eventually { downloader.phase != .downloading }
    }

    private func installed(_ file: ModelFiles.File) -> URL { paths.models.appending(path: file.name) }
    private func partial(_ file: ModelFiles.File) -> URL { paths.partialDownloads.appending(path: file.name + ".partial") }

    @Test("Both files download, verify and move into Models; the partial files go")
    func downloadsAndInstalls() async throws {
        let first = body(3_000_000), second = body(1_200_000).reversed()
        let files = [fakeFile(first), fakeFile(Data(second))]
        LookoutFakeModelServer.serve(files[0].name, first)
        LookoutFakeModelServer.serve(files[1].name, Data(second))
        let downloader = downloader(files)
        var reported: [Double?] = []
        downloader.onProgress = { reported.append($0) }
        var finishedCalls = 0
        downloader.onFinished = { finishedCalls += 1 }
        downloader.start()
        #expect(await finished(downloader))
        #expect(downloader.phase == .finished && downloader.isReady && finishedCalls == 1)
        #expect(try Data(contentsOf: installed(files[0])) == first)
        #expect(try Data(contentsOf: installed(files[1])) == Data(second))
        #expect(!FileManager.default.fileExists(atPath: partial(files[0]).path))
        #expect(reported.last == .some(nil), "the card's progress ends")
        #expect(reported.compactMap { $0 }.max() ?? 0 > 0)
        try? FileManager.default.removeItem(at: base)
    }

    @Test("A checksum mismatch rejects the file: nothing in Models, the partial deleted")
    func checksumMismatch() async throws {
        let data = body(500_000)
        let file = fakeFile(data, sha: String(repeating: "0", count: 64))
        LookoutFakeModelServer.serve(file.name, data)
        let downloader = downloader([file])
        downloader.start()
        #expect(await finished(downloader))
        #expect(downloader.phase == .failed(.checksumMismatch))
        #expect(!FileManager.default.fileExists(atPath: installed(file).path))
        #expect(!FileManager.default.fileExists(atPath: partial(file).path))
        try? FileManager.default.removeItem(at: base)
    }

    @Test("An interrupted download resumes with a range request and installs the whole file")
    func resumes() async throws {
        let data = body(2_000_000)
        let file = fakeFile(data)
        LookoutFakeModelServer.serve(file.name, data, failAfter: 700_000)
        let downloader = downloader([file])
        downloader.start()
        #expect(await finished(downloader))
        #expect(downloader.error?.analyticsCategory == .network)
        // What arrived before the connection dropped stays (URLSession may hold back the last bytes it had).
        let kept = try #require(try FileManager.default.attributesOfItem(atPath: partial(file).path)[.size] as? Int64)
        #expect(kept > 0 && kept <= 700_000)
        #expect(!FileManager.default.fileExists(atPath: installed(file).path), "not renamed before it verifies")
        downloader.start()
        #expect(await finished(downloader))
        #expect(downloader.phase == .finished)
        #expect(LookoutFakeModelServer.ranges(file.name) == [nil, "bytes=\(kept)-"])
        #expect(try Data(contentsOf: installed(file)) == data)
        try? FileManager.default.removeItem(at: base)
    }

    @Test("A server that ignores the range sends the whole file again, and the partial starts over")
    func wholeFileInsteadOfRange() async throws {
        let data = body(800_000)
        let file = fakeFile(data)
        try FileManager.default.createDirectory(at: paths.partialDownloads, withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 300_000).write(to: partial(file))
        LookoutFakeModelServer.serve(file.name, data, honorsRange: false)
        let downloader = downloader([file])
        downloader.start()
        #expect(await finished(downloader))
        #expect(downloader.phase == .finished)
        #expect(try Data(contentsOf: installed(file)) == data)
        try? FileManager.default.removeItem(at: base)
    }

    @Test("Too little free space stops the download before any request")
    func diskSpace() async {
        let data = body(400_000)
        let file = fakeFile(data)
        LookoutFakeModelServer.serve(file.name, data)
        let downloader = downloader([file], freeSpace: 1_000)
        downloader.start()
        #expect(await finished(downloader))
        guard case .failed(.notEnoughSpace(let needed, let available)) = downloader.phase else {
            Issue.record("expected notEnoughSpace, got \(downloader.phase)")
            return
        }
        #expect(needed == 400_000 + LookoutDiskSpace.headroom && available == 1_000)
        #expect(LookoutFakeModelServer.ranges(file.name).isEmpty)
        try? FileManager.default.removeItem(at: base)
    }

    @Test("Space needed counts what's already downloaded, plus headroom")
    func requiredSpace() {
        let files = [ModelFiles.File(name: "a", bytes: 1_000, sha256: ""), ModelFiles.File(name: "b", bytes: 500, sha256: "")]
        #expect(LookoutDiskSpace.required(for: files, alreadyDownloaded: ["a": 400]) == 1_100 + LookoutDiskSpace.headroom)
        #expect(LookoutDiskSpace.required(for: ModelFiles.all, alreadyDownloaded: [:]) < 1_000_000_000,
                "about 1 GB for a fresh download")
    }

    @Test("Downloads go to Hugging Face over HTTPS only")
    func hosts() {
        #expect(LookoutDownloadHosts.isAllowed(ModelFiles.text.url))
        #expect(LookoutDownloadHosts.isAllowed(URL(string: "https://cdn-lfs.hf.co/repos/x")))
        #expect(LookoutDownloadHosts.isAllowed(URL(string: "https://cas-bridge.xethub.hf.co/x")))
        #expect(!LookoutDownloadHosts.isAllowed(URL(string: "http://huggingface.co/x")))
        #expect(!LookoutDownloadHosts.isAllowed(URL(string: "https://huggingface.co.example.com/x")))
        #expect(!LookoutDownloadHosts.isAllowed(URL(string: "https://example.com/huggingface.co")))
        #expect(ModelFiles.text.url.absoluteString.contains("/resolve/\(ModelFiles.revision)/"))
    }

    @Test("A downloader that may not download never starts, and never reads the disk")
    func inert() {
        let downloader = LookoutModelDownloader.inert()
        downloader.start()
        #expect(downloader.phase == .idle && !downloader.isDownloading)
    }

    // MARK: Installing

    @Test("A cancelled install stops hashing between pieces and keeps the partial file; a verified one moves")
    func cancelledInstallKeepsThePartialFile() async throws {
        let contents = Data(repeating: 0x5A, count: (8 << 20) * 2 + 100)   // three 8 MB pieces
        let file = fakeFile(contents)
        let partial = partial(file)
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: partial)
        var checks = 0
        #expect(throws: CancellationError.self) {
            try LookoutModelInstaller.installNow(file, from: partial, into: paths.models) {
                checks += 1
                if checks == 2 { throw CancellationError() }   // before the second piece
            }
        }
        #expect(checks == 2)
        #expect(FileManager.default.fileExists(atPath: partial.path))           // kept for the next run
        #expect(!FileManager.default.fileExists(atPath: installed(file).path))
        // A caller cancelled before it starts hashes nothing.
        let task = Task { try await LookoutModelInstaller.install(file, from: partial, into: paths.models) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(FileManager.default.fileExists(atPath: partial.path))
        // Run through, off the cooperative pool: verified and moved into place.
        try await LookoutModelInstaller.install(file, from: partial, into: paths.models)
        #expect(try Data(contentsOf: installed(file)) == contents)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }
}

/// A fake Hugging Face for `LookoutModelDownloaderTests`: serves registered bodies by file name, honoring `Range`
/// with `206` (or ignoring it with `200`), and can drop the connection after some bytes once. It records each
/// request's `Range` header. Never touches the network.
nonisolated final class LookoutFakeModelServer: URLProtocol, @unchecked Sendable {
    private struct Plan {
        var body: Data
        var failAfter: Int?
        var honorsRange: Bool
        var ranges: [String?] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var plans: [String: Plan] = [:]

    static func serve(_ name: String, _ body: Data, failAfter: Int? = nil, honorsRange: Bool = true) {
        lock.withLock { plans[name] = Plan(body: body, failAfter: failAfter, honorsRange: honorsRange) }
    }

    static func ranges(_ name: String) -> [String?] {
        lock.withLock { plans[name]?.ranges ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let range = request.value(forHTTPHeaderField: "Range")
        let plan = Self.lock.withLock { () -> Plan? in
            Self.plans[url.lastPathComponent]?.ranges.append(range)
            let plan = Self.plans[url.lastPathComponent]
            Self.plans[url.lastPathComponent]?.failAfter = nil
            return plan
        }
        guard let plan else {
            respond(url, status: 404, headers: [:], body: Data())
            return
        }
        var start = 0
        var status = 200
        var headers = ["Content-Length": "\(plan.body.count)"]
        if plan.honorsRange, let range, range.hasPrefix("bytes="), let from = Int(range.dropFirst(6).dropLast()) {
            guard from < plan.body.count else {
                respond(url, status: 416, headers: [:], body: Data())
                return
            }
            start = from
            status = 206
            headers = ["Content-Length": "\(plan.body.count - from)",
                       "Content-Range": "bytes \(from)-\(plan.body.count - 1)/\(plan.body.count)"]
        }
        let slice = plan.body.subdata(in: start..<plan.body.count)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let failAfter = plan.failAfter {
            send(slice.prefix(failAfter))
            // A moment later, as a real connection drops, so the bytes before it reach the session first.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }
        send(slice)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Delivers `data` in 64 KB pieces, as a network would.
    private func send(_ data: Data) {
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + 64 * 1024, data.endIndex)
            client?.urlProtocol(self, didLoad: data.subdata(in: offset..<end))
            offset = end
        }
    }

    override func stopLoading() {}

    private func respond(_ url: URL, status: Int, headers: [String: String], body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

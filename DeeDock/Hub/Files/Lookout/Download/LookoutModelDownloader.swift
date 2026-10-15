import Foundation
import Observation

/// Downloads EmbeddingGemma 2 for Lookout: `ModelFiles.text`, then `ModelFiles.media`, from Hugging Face at the
/// pinned revision, each into `LookoutPaths.partialDownloads`, verified, and only then moved into
/// `LookoutPaths.models`.
///
/// - Resumes: an unfinished file continues with an HTTP range request, also after the app quit
///   (`LookoutModelTransfer`).
/// - Checks the free space first (`LookoutDiskSpace`), about 1 GB for a fresh download.
/// - Reports each file's state and the total progress (`progress`), and `onProgress` for the Hub's download card and
///   status chip.
/// - Reports one `lookout_model_download` per run: completed, failed (with a category) or cancelled.
///
/// It downloads only when asked (onboarding, once the person continues past the folder access step). One exists for
/// the app's lifetime (`LookoutSetupCoordinator` owns it), so closing onboarding doesn't stop a download. Under the
/// test host and in previews `live()` returns one that never downloads.
///
/// Main actor. The one download task is cancelled by `cancel()` and replaced by nothing else while it runs.
@MainActor @Observable
final class LookoutModelDownloader {
    /// One file's state.
    enum FileState: Equatable, Sendable {
        /// Not there yet and not being fetched.
        case waiting
        /// Bytes in the partial file so far.
        case downloading(received: Int64)
        /// Checking the SHA-256.
        case verifying
        /// Verified and in place.
        case ready
    }

    /// The download as a whole.
    enum Phase: Equatable, Sendable {
        case idle
        case downloading
        /// Both files are in place.
        case finished
        case failed(LookoutDownloadError)
    }

    /// The files, in download order.
    let files: [ModelFiles.File]
    private(set) var states: [String: FileState] = [:]
    private(set) var phase: Phase = .idle

    /// Runs on the main actor when the overall progress changes by a percent or more, or ends (nil).
    @ObservationIgnored var onProgress: ((Double?) -> Void)?
    /// Runs on the main actor when both files are in place after a download.
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private let paths: LookoutPaths
    @ObservationIgnored private let configuration: URLSessionConfiguration
    @ObservationIgnored private let availableSpace: @Sendable (URL) -> Int64?
    @ObservationIgnored private let canDownload: Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var reportedPercent: Int?

    /// - Parameters:
    ///   - paths: Where the partial files and the models go.
    ///   - files: What to download; tests pass tiny fakes.
    ///   - configuration: The URL session's configuration; tests add a fake `URLProtocol`.
    ///   - availableSpace: Free bytes at a folder (`LookoutDiskSpace.available`); tests pass a fixed answer.
    ///   - canDownload: False for a downloader that must never fetch anything (previews, the test host).
    init(paths: LookoutPaths, files: [ModelFiles.File] = ModelFiles.all,
         configuration: URLSessionConfiguration = .default,
         availableSpace: @escaping @Sendable (URL) -> Int64? = { LookoutDiskSpace.available(at: $0) },
         canDownload: Bool) {
        self.paths = paths
        self.files = files
        self.configuration = configuration
        self.availableSpace = availableSpace
        self.canDownload = canDownload
        refresh()
    }

    /// The real downloader into `~/Library/Application Support/DDock/Lookout`; one that never downloads under the
    /// test host and in previews.
    static func live(paths: LookoutPaths = .standard) -> LookoutModelDownloader {
        let allowed = !HostEnvironment.isTestHost && !HostEnvironment.isPreview
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        return LookoutModelDownloader(paths: paths, configuration: configuration, canDownload: allowed)
    }

    /// A downloader that never downloads, with every file in `state`: previews and tests of other features.
    static func inert(state: FileState = .waiting) -> LookoutModelDownloader {
        let downloader = LookoutModelDownloader(
            paths: LookoutPaths(base: FileManager.default.temporaryDirectory.appending(path: "LookoutInertDownload")),
            canDownload: false)
        for file in downloader.files { downloader.states[file.name] = state }
        if state == .ready { downloader.phase = .finished }
        return downloader
    }

    // MARK: State

    /// Both files are in place.
    var isReady: Bool { files.allSatisfy { states[$0.name] == .ready } }

    /// True while a download task runs.
    var isDownloading: Bool { phase == .downloading }

    /// The error that stopped the last run, if it failed.
    var error: LookoutDownloadError? {
        if case .failed(let error) = phase { error } else { nil }
    }

    /// 0…1 over both files while downloading or verifying; nil otherwise.
    var progress: Double? {
        guard isDownloading else { return nil }
        let total = files.reduce(0) { $0 + $1.bytes }
        guard total > 0 else { return nil }
        let done = files.reduce(Int64(0)) { sum, file in
            switch states[file.name] {
            case .downloading(let received)?: sum + received
            case .verifying?, .ready?: sum + file.bytes
            default: sum
            }
        }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    /// One file's progress, 0…1.
    func fraction(of file: ModelFiles.File) -> Double {
        switch states[file.name] {
        case .downloading(let received)?: file.bytes > 0 ? min(Double(received) / Double(file.bytes), 1) : 0
        case .verifying?, .ready?: 1
        default: 0
        }
    }

    /// Re-reads which files are in place and how much of the others is downloaded. Doesn't touch a running download,
    /// and a downloader that may not download never reads the disk (its states stay as made).
    func refresh() {
        guard canDownload, !isDownloading else { return }
        let missing = Set(ModelFiles.missing(of: files, in: paths.models).map(\.name))
        for file in files {
            if !missing.contains(file.name) {
                states[file.name] = .ready
            } else if let partial = partialSize(of: file), partial > 0 {
                states[file.name] = .downloading(received: partial)
            } else {
                states[file.name] = .waiting
            }
        }
        if isReady { phase = .finished }
    }

    // MARK: Actions

    /// Starts or resumes the download. Does nothing when it runs already, both files are there, or this downloader
    /// may not download.
    func start() {
        guard canDownload, task == nil else { return }
        refresh()
        guard !isReady else { return }
        phase = .downloading
        reportProgress()
        task = Task { [weak self] in await self?.run() }
    }

    /// Stops the download; the partial file stays, so the next `start` resumes it.
    func cancel() {
        task?.cancel()
    }

    /// Cancels the download and waits until it has stopped, before its files are deleted.
    func stop() async {
        let task = task
        task?.cancel()
        await task?.value
    }

    // MARK: Run

    private func run() async {
        let started = ContinuousClock.now
        let outcome: (AnalyticsLookoutDownloadOutcome, AnalyticsLookoutDownloadError?)
        do {
            try checkSpace()
            for file in files where states[file.name] != .ready {
                try await fetch(file)
            }
            phase = .finished
            outcome = (.completed, nil)
        } catch is CancellationError {
            refreshAfterStop()
            outcome = (.cancelled, nil)
        } catch {
            let failure = LookoutDownloadError.from(error)
            refreshAfterStop()
            phase = .failed(failure)
            outcome = (.failed, failure.analyticsCategory)
        }
        task = nil
        reportProgress()
        let seconds = Int((ContinuousClock.now - started).components.seconds)
        Analytics.track(.lookoutModelDownload(outcome: outcome.0, seconds: seconds, error: outcome.1))
        if outcome.0 == .completed { onFinished?() }
    }

    private func checkSpace() throws {
        let downloaded = Dictionary(uniqueKeysWithValues: files.map { ($0.name, partialSize(of: $0) ?? 0) })
        let missing = files.filter { states[$0.name] != .ready }
        let needed = LookoutDiskSpace.required(for: missing, alreadyDownloaded: downloaded)
        if let available = availableSpace(paths.base), available < needed {
            throw LookoutDownloadError.notEnoughSpace(needed: needed, available: available)
        }
    }

    /// Downloads, verifies and installs one file. A partial file the server won't continue is deleted and fetched
    /// once more from the start.
    private func fetch(_ file: ModelFiles.File) async throws {
        let partial = partialURL(of: file)
        states[file.name] = .downloading(received: partialSize(of: file) ?? 0)
        let name = file.name
        // A main-actor class is Sendable; the transfer holds it only while it runs.
        let progress: @Sendable (Int64) -> Void = { received in
            Task { @MainActor in self.received(received, for: name) }
        }
        do {
            try await LookoutModelTransfer.run(url: file.url, partial: partial, expectedBytes: file.bytes,
                                               configuration: configuration, progress: progress)
        } catch is LookoutModelTransfer.RangeNotSatisfiable {
            try? FileManager.default.removeItem(at: partial)
            states[file.name] = .downloading(received: 0)
            try await LookoutModelTransfer.run(url: file.url, partial: partial, expectedBytes: file.bytes,
                                               configuration: configuration, progress: progress)
        }
        try Task.checkCancellation()
        states[file.name] = .verifying
        reportProgress()
        try await LookoutModelInstaller.install(file, from: partial, into: paths.models)
        states[file.name] = .ready
        reportProgress()
    }

    /// A progress report from the transfer's queue. Late reports after the file moved on are ignored.
    private func received(_ bytes: Int64, for name: String) {
        guard case .downloading? = states[name] else { return }
        states[name] = .downloading(received: bytes)
        reportProgress()
    }

    /// After a stop, files keep what they reached: in place, or partly downloaded.
    private func refreshAfterStop() {
        phase = .idle
        refresh()
    }

    private func reportProgress() {
        let progress = progress
        let percent = progress.map { Int(($0 * 100).rounded(.down)) }
        guard percent != reportedPercent else { return }
        reportedPercent = percent
        onProgress?(progress)
    }

    private func partialURL(of file: ModelFiles.File) -> URL {
        paths.partialDownloads.appending(path: file.name + ".partial", directoryHint: .notDirectory)
    }

    private func partialSize(of file: ModelFiles.File) -> Int64? {
        try? FileManager.default.attributesOfItem(atPath: partialURL(of: file).path)[.size] as? Int64
    }

    isolated deinit {
        task?.cancel()
    }
}

nonisolated extension ModelFiles {
    /// The files of `files` that aren't in `folder` yet (`missing(in:)` for any list, so tests can pass fakes).
    static func missing(of files: [File], in folder: URL) -> [File] {
        files.filter { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.name).path) }
    }
}

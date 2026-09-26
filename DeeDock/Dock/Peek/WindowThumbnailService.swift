import AppKit
import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

nonisolated struct WindowCaptureCandidate: Equatable, Sendable {
    let id: CGWindowID
    let processIdentifier: pid_t
    let title: String?
    let frame: CGRect
    let isOnScreen: Bool
}

nonisolated enum WindowThumbnailServiceError: Error, Equatable, Sendable {
    case permissionRequired
    case unavailable
}

/// Projects ScreenCaptureKit's public window metadata into session-scoped Peek summaries.
nonisolated enum WindowCaptureDiscovery {
    static func summaries(candidates: [WindowCaptureCandidate], processIdentifiers: Set<pid_t>,
                          sessionID: UUID) -> [ApplicationWindowSummary] {
        candidates.compactMap { candidate in
            guard processIdentifiers.contains(candidate.processIdentifier),
                  candidate.frame.width > 1, candidate.frame.height > 1 else { return nil }
            return ApplicationWindowSummary(
                token: ApplicationWindowToken(sessionID: sessionID, id: UUID()),
                processIdentifier: candidate.processIdentifier,
                title: candidate.title,
                frame: candidate.frame,
                // ScreenCaptureKit does not distinguish minimized windows from windows on another Space,
                // so off-screen windows keep a card flagged `isOffScreen` instead of vanishing.
                isMinimized: false,
                isMain: false,
                isOffScreen: !candidate.isOnScreen
            )
        }
    }
}

/// Conservative public-API join between Accessibility and ScreenCaptureKit windows.
nonisolated enum WindowThumbnailMatcher {
    static func matches(summaries: [ApplicationWindowSummary], candidates: [WindowCaptureCandidate])
        -> [ApplicationWindowToken: CGWindowID] {
        var matches: [ApplicationWindowToken: CGWindowID] = [:]
        for summary in summaries {
            guard let frame = summary.frame else { continue }
            let title = normalized(summary.title)
            let eligible = candidates.filter { candidate in
                candidate.processIdentifier == summary.processIdentifier
                    && (title == nil || normalized(candidate.title) == title)
                    && close(frame, candidate.frame)
            }
            if eligible.count == 1 { matches[summary.token] = eligible[0].id }
        }
        return matches
    }

    /// Match freshly discovered AX metadata to the portal's bound ScreenCaptureKit source.
    /// Apply the same title normalization and two-point tolerance as thumbnail binding, refusing ambiguity.
    static func matchingWindow(_ source: ApplicationWindowSummary,
                               among windows: [ApplicationWindowSummary]) -> ApplicationWindowToken? {
        guard let frame = source.frame else { return nil }
        let title = normalized(source.title)
        let eligible = windows.filter { window in
            guard let candidateFrame = window.frame else { return false }
            return window.processIdentifier == source.processIdentifier
                && (title == nil || normalized(window.title) == title)
                && close(frame, candidateFrame)
        }
        return eligible.count == 1 ? eligible[0].token : nil
    }

    private static func normalized(_ title: String?) -> String? {
        guard let value = title?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value.precomposedStringWithCanonicalMapping
    }

    private static func close(_ first: CGRect, _ second: CGRect) -> Bool {
        [first.minX - second.minX, first.minY - second.minY,
         first.width - second.width, first.height - second.height].allSatisfy { abs($0) <= 2 }
    }
}

/// One Peek card image. `isCached` marks a picture reused from an earlier capture of the same
/// window because a fresh capture failed, typically for a minimized or hidden window.
nonisolated struct WindowThumbnail: Sendable {
    let image: CGImage
    let isCached: Bool
}

/// Memory-only, least-recently-used store of the last good capture per window.
///
/// Keyed by process and window server window ID so a Peek session's transient tokens never
/// matter. An entry is reused only when the process launch date still matches, the window keeps
/// its size within the matcher's two-point tolerance, and the pixel budget is identical, so a
/// cached picture can never letterbox differently from the fresh one that later replaces it.
/// Nothing here is written to disk.
nonisolated struct WindowThumbnailCache {
    struct Key: Hashable {
        let processIdentifier: pid_t
        let windowID: CGWindowID
    }

    private struct Entry {
        let image: CGImage
        let sourceSize: CGSize
        let budget: CGSize
        let launchDate: Date?
        var lastUse: UInt64
    }

    let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0

    init(capacity: Int = 32) { self.capacity = max(1, capacity) }

    var count: Int { entries.count }

    /// Records a fresh capture, evicting the least recently used entry beyond `capacity`.
    mutating func store(_ image: CGImage, for key: Key, sourceSize: CGSize, budget: CGSize, launchDate: Date?) {
        clock += 1
        entries[key] = Entry(image: image, sourceSize: sourceSize, budget: budget,
                             launchDate: launchDate, lastUse: clock)
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries.removeValue(forKey: oldest.key)
        }
    }

    /// Returns the stored picture when it still describes this window at this budget. Touches the entry.
    mutating func image(for key: Key, sourceSize: CGSize, budget: CGSize, launchDate: Date?) -> CGImage? {
        guard var entry = entries[key], entry.launchDate == launchDate, entry.budget == budget,
              abs(entry.sourceSize.width - sourceSize.width) <= 2,
              abs(entry.sourceSize.height - sourceSize.height) <= 2 else { return nil }
        clock += 1
        entry.lastUse = clock
        entries[key] = entry
        return entry.image
    }

    /// Drops every entry for a process, for example after it terminates.
    mutating func removeAll(for processIdentifier: pid_t) {
        entries = entries.filter { $0.key.processIdentifier != processIdentifier }
    }

    mutating func removeAll() { entries.removeAll() }
}

protocol WindowThumbnailServicing: Actor {
    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws
        -> [ApplicationWindowSummary]
    /// `size` is logical points. Each window is captured at that size times its own display scale.
    /// A window whose fresh capture fails may return its last good picture flagged `isCached`.
    func capture(_ windows: [ApplicationWindowSummary], size: CGSize) async -> [ApplicationWindowToken: WindowThumbnail]
    /// `pixels` is an exact pixel budget. It is not divided or multiplied by a display scale.
    func capture(_ window: ApplicationWindowSummary, fittingPixels pixels: CGSize) async -> CGImage?
    func stop()
}

/// One-shot, memory-only ScreenCaptureKit capture. Native window handles never leave this actor.
///
/// The actor also owns the thumbnail cache so window server IDs stay inside it. The cache outlives
/// a Peek presentation on purpose: `stop()` ends captures but keeps the pictures, which is what
/// lets a later Peek show a minimized window whose live capture no longer succeeds. The cache is
/// cleared whenever Screen Recording access is found missing, and per process when that process
/// terminates.
actor ScreenCaptureWindowThumbnailService: WindowThumbnailServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock",
                                       category: "WindowPeekCapture")
    private var cache = WindowThumbnailCache()
    private var terminationObserver: (any NSObjectProtocol)?

    init() {
        Task { await self.observeTerminations() }
    }

    /// A terminated process can never validate a cache entry again, so drop its pictures early.
    private func observeTerminations() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            Task { await self?.forget(processIdentifier: pid) }
        }
    }

    private func forget(processIdentifier: pid_t) { cache.removeAll(for: processIdentifier) }

    deinit {
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
    }

    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws
        -> [ApplicationWindowSummary] {
        guard CGPreflightScreenCaptureAccess() else { throw WindowThumbnailServiceError.permissionRequired }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            return WindowCaptureDiscovery.summaries(
                candidates: Self.candidates(from: content),
                processIdentifiers: Set(processes.map(\.processIdentifier)),
                sessionID: sessionID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("ScreenCaptureKit window discovery failed: \(error.localizedDescription, privacy: .public)")
            throw WindowThumbnailServiceError.unavailable
        }
    }

    func capture(_ windows: [ApplicationWindowSummary], size: CGSize) async -> [ApplicationWindowToken: WindowThumbnail] {
        await capture(windows, useCache: true) { filter in
            WindowScreenshot.backingPixels(for: size, pointPixelScale: CGFloat(filter.pointPixelScale))
        }
    }

    /// The enlarged preview's budgets vary per hero, so it neither reads nor fills the cache.
    func capture(_ window: ApplicationWindowSummary, fittingPixels pixels: CGSize) async -> CGImage? {
        await capture([window], useCache: false) { _ in pixels }[window.token]?.image
    }

    /// One enumeration and one match pass. `budget` receives the filter so a point size can use that window's scale.
    ///
    /// Minimized and off-screen windows are attempted like any other: the window server keeps
    /// their backing store, and whether the public screenshot API returns it is decided per macOS
    /// release. A failed attempt falls back to the cache when `useCache` is set.
    private func capture(_ windows: [ApplicationWindowSummary], useCache: Bool,
                         budget: (SCContentFilter) -> CGSize) async -> [ApplicationWindowToken: WindowThumbnail] {
        guard CGPreflightScreenCaptureAccess() else { cache.removeAll(); return [:] }
        guard !windows.isEmpty else { return [:] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            let candidates = Self.candidates(from: content)
            let matches = WindowThumbnailMatcher.matches(summaries: windows, candidates: candidates)
            let native = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
            var result: [ApplicationWindowToken: WindowThumbnail] = [:]
            for summary in windows {
                try Task.checkCancellation()
                guard let id = matches[summary.token], let window = native[id] else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let pixels = budget(filter)
                let key = WindowThumbnailCache.Key(processIdentifier: summary.processIdentifier, windowID: id)
                let launchDate = NSRunningApplication(processIdentifier: summary.processIdentifier)?.launchDate
                do {
                    let image = try await WindowScreenshot.capture(
                        filter: filter, source: window.frame.size, fittingPixels: pixels)
                    result[summary.token] = WindowThumbnail(image: image, isCached: false)
                    if useCache {
                        cache.store(image, for: key, sourceSize: window.frame.size, budget: pixels, launchDate: launchDate)
                    }
                } catch is CancellationError {
                    return [:]
                } catch {
                    Self.logger.error("ScreenCaptureKit thumbnail failed: \(error.localizedDescription, privacy: .public)")
                    if useCache, let image = cache.image(for: key, sourceSize: window.frame.size,
                                                         budget: pixels, launchDate: launchDate) {
                        result[summary.token] = WindowThumbnail(image: image, isCached: true)
                    }
                    continue
                }
            }
            return result
        } catch {
            Self.logger.error("ScreenCaptureKit thumbnail enumeration failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    func stop() {}

    private static func candidates(from content: SCShareableContent) -> [WindowCaptureCandidate] {
        content.windows.compactMap { window in
            guard window.windowLayer == 0, let application = window.owningApplication,
                  application.processID != ProcessInfo.processInfo.processIdentifier else { return nil }
            return WindowCaptureCandidate(id: window.windowID, processIdentifier: application.processID,
                                          title: window.title, frame: window.frame, isOnScreen: window.isOnScreen)
        }
    }

}

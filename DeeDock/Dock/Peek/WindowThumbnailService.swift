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
                  candidate.isOnScreen,
                  candidate.frame.width > 1, candidate.frame.height > 1 else { return nil }
            return ApplicationWindowSummary(
                token: ApplicationWindowToken(sessionID: sessionID, id: UUID()),
                processIdentifier: candidate.processIdentifier,
                title: candidate.title,
                frame: candidate.frame,
                // ScreenCaptureKit does not distinguish minimized windows from windows on another Space.
                isMinimized: false,
                isMain: false
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

protocol WindowThumbnailServicing: Actor {
    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws
        -> [ApplicationWindowSummary]
    func capture(_ windows: [ApplicationWindowSummary], size: CGSize) async -> [ApplicationWindowToken: CGImage]
    func stop()
}

/// One-shot, memory-only ScreenCaptureKit capture. Native window handles never leave this actor.
actor ScreenCaptureWindowThumbnailService: WindowThumbnailServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock",
                                       category: "WindowPeekCapture")

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

    func capture(_ windows: [ApplicationWindowSummary], size: CGSize) async -> [ApplicationWindowToken: CGImage] {
        guard CGPreflightScreenCaptureAccess(), !windows.isEmpty else { return [:] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            let candidates = Self.candidates(from: content)
            let matches = WindowThumbnailMatcher.matches(summaries: windows, candidates: candidates)
            let native = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
            var result: [ApplicationWindowToken: CGImage] = [:]
            for summary in windows where !summary.isMinimized {
                try Task.checkCancellation()
                guard let id = matches[summary.token], let window = native[id] else { continue }
                do {
                    let image = try await WindowScreenshot.capture(window,
                        fittingPixels: CGSize(width: size.width * 2, height: size.height * 2))
                    result[summary.token] = image
                } catch is CancellationError {
                    return [:]
                } catch {
                    Self.logger.error("ScreenCaptureKit thumbnail failed: \(error.localizedDescription, privacy: .public)")
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

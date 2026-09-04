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
                let target = Self.pixelSize(for: window.frame.size, fitting: size)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(target.width)
                configuration.height = Int(target.height)
                configuration.showsCursor = false
                configuration.capturesAudio = false
                configuration.ignoreShadowsSingleWindow = true
                configuration.includeChildWindows = true
                do {
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: window),
                        configuration: configuration
                    )
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
            guard window.windowLayer == 0, let application = window.owningApplication else { return nil }
            return WindowCaptureCandidate(id: window.windowID, processIdentifier: application.processID,
                                          title: window.title, frame: window.frame, isOnScreen: window.isOnScreen)
        }
    }

    private static func pixelSize(for source: CGSize, fitting logical: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else {
            return CGSize(width: logical.width * 2, height: logical.height * 2)
        }
        let scale = min(logical.width / source.width, logical.height / source.height) * 2
        return CGSize(width: max(1, (source.width * scale).rounded()),
                      height: max(1, (source.height * scale).rounded()))
    }
}

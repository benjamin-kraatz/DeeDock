import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit
import Vision

/// Public, display-safe metadata for a currently visible window.
///
/// This is the shared discovery value for Session Capsules and the planned Window Scout. It is
/// deliberately independent of either feature's presentation and contains no native window handle.
nonisolated struct WindowContextCandidate: Equatable, Identifiable, Sendable {
    let id: CGWindowID
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
    let title: String?
    let frame: CGRect
}

/// Ephemeral visible content for one chosen window. Callers must not persist the image or OCR.
nonisolated struct WindowContextSnapshot: @unchecked Sendable {
    let candidate: WindowContextCandidate
    let image: CGImage?
    let recognizedText: String
}

nonisolated enum WindowContextCaptureError: Error, Equatable, Sendable {
    case permissionRequired
    case unavailable
    case noWindows
}

/// Feature-neutral boundary for one-time discovery and bounded visible-content capture.
nonisolated protocol WindowContextCapturing: Actor {
    func discover() async throws -> [WindowContextCandidate]
    func capture(_ candidates: [WindowContextCandidate]) async throws -> [WindowContextSnapshot]
}

/// One-shot ScreenCaptureKit capture with on-device Vision OCR.
///
/// Images remain local and live only in the returned draft-generation task. The service captures
/// selected windows serially so a large desktop cannot create an unbounded image-processing burst.
actor ScreenCaptureWindowContextService: WindowContextCapturing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock",
                                       category: "WindowContextCapture")
    private static let captureSize = CGSize(width: 1_200, height: 900)

    func discover() async throws -> [WindowContextCandidate] {
        guard CGPreflightScreenCaptureAccess() else { throw WindowContextCaptureError.permissionRequired }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let candidates = content.windows.compactMap { window -> WindowContextCandidate? in
                guard window.windowLayer == 0, window.isOnScreen,
                      window.frame.width > 80, window.frame.height > 60,
                      let application = window.owningApplication,
                      application.processID != ownPID else { return nil }
                return WindowContextCandidate(
                    id: window.windowID,
                    processIdentifier: application.processID,
                    applicationName: application.applicationName,
                    bundleIdentifier: application.bundleIdentifier.isEmpty ? nil : application.bundleIdentifier,
                    title: Self.normalized(window.title),
                    frame: window.frame
                )
            }
            .sorted {
                if $0.applicationName != $1.applicationName {
                    return $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending
                }
                return ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
            }
            guard !candidates.isEmpty else { throw WindowContextCaptureError.noWindows }
            return candidates
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WindowContextCaptureError {
            throw error
        } catch {
            Self.logger.error("Window discovery failed: \(error.localizedDescription, privacy: .public)")
            throw WindowContextCaptureError.unavailable
        }
    }

    func capture(_ candidates: [WindowContextCandidate]) async throws -> [WindowContextSnapshot] {
        guard CGPreflightScreenCaptureAccess() else { throw WindowContextCaptureError.permissionRequired }
        let selected = Array(candidates.prefix(SessionCapsuleDocument.maximumWindowsPerCapsule))
        guard !selected.isEmpty else { throw WindowContextCaptureError.noWindows }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            let windows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
            var snapshots: [WindowContextSnapshot] = []
            snapshots.reserveCapacity(selected.count)

            for candidate in selected {
                try Task.checkCancellation()
                guard let window = windows[candidate.id] else {
                    snapshots.append(WindowContextSnapshot(candidate: candidate, image: nil, recognizedText: ""))
                    continue
                }
                do {
                    let image = try await Self.capture(window)
                    try Task.checkCancellation()
                    let text = try await Self.recognizeText(in: image)
                    snapshots.append(WindowContextSnapshot(candidate: candidate, image: image,
                                                           recognizedText: text))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Self.logger.error("Window context failed: \(error.localizedDescription, privacy: .public)")
                    snapshots.append(WindowContextSnapshot(candidate: candidate, image: nil, recognizedText: ""))
                }
            }
            return snapshots
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Window capture enumeration failed: \(error.localizedDescription, privacy: .public)")
            throw WindowContextCaptureError.unavailable
        }
    }

    private nonisolated static func capture(_ window: SCWindow) async throws -> CGImage {
        let scale = min(captureSize.width / max(window.frame.width, 1),
                        captureSize.height / max(window.frame.height, 1))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * min(scale, 2)).rounded()))
        configuration.height = max(1, Int((window.frame.height * min(scale, 2)).rounded()))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        )
    }

    private nonisolated static func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.map(\.transcript).joined(separator: "\n")
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

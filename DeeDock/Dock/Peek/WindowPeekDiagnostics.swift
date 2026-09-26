import AppKit
import OSLog

/// Geometry and capture facts from the most recent Peek presentation, for support reports.
///
/// `WindowPeekCoordinator` records a snapshot after each thumbnail batch; Settings › Window Peek ›
/// Compatibility copies the latest report to the clipboard. The report holds numbers and settings
/// only. Window titles, app names, and pixels never appear in it.
@MainActor @Observable
final class WindowPeekDiagnostics {
    static let shared = WindowPeekDiagnostics()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock",
                                       category: "WindowPeekDiagnostics")

    /// One captured window: its frame in points and the bitmap ScreenCaptureKit returned, if any.
    nonisolated struct Capture: Sendable {
        let frame: CGRect
        let pixels: CGSize?
    }

    /// The latest report, or `nil` until a Peek has shown windows since launch.
    private(set) var report: String?

    /// Replaces the report and mirrors it to the unified log at info level.
    func record(settings: DockSettings, placement: CGRect, panel: CGRect, screen: NSScreen?,
                captures: [Capture]) {
        let card = WindowPeekGeometry.cardSize(settings)
        let thumbnail = settings.windowPeekSize.thumbnailSize
        var lines: [String] = []
        lines.append("DDock \(AppVersionInfo.current.settingsValue) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Scroll bars: \(NSScroller.preferredScrollerStyle == .legacy ? "legacy (always shown)" : "overlay")")
        lines.append("Peek: size=\(settings.windowPeekSize.rawValue) layout=\(settings.windowPeekLayout.rawValue) "
                     + "style=\(settings.windowPeekStyle.rawValue) split=\(settings.windowPeekSplitEnabled) "
                     + "enlarge=\(settings.windowPeekEnlargeEnabled)")
        lines.append("Compatibility: noScrollBars=\(settings.windowPeekNeverShowsScrollBars) "
                     + "keepPanelSize=\(settings.windowPeekKeepsPanelSize) "
                     + "automaticResolution=\(settings.windowPeekCapturesAtAutomaticResolution)")
        if let screen {
            lines.append("Screen: frame \(Self.text(screen.frame)) visible \(Self.text(screen.visibleFrame)) "
                         + "scale \(Self.text(screen.backingScaleFactor))")
        } else {
            lines.append("Screen: unknown")
        }
        lines.append("Card: \(Self.text(card)) thumbnail \(Self.text(thumbnail))")
        lines.append("Panel: computed \(Self.text(placement)) actual \(Self.text(panel))")
        lines.append("Windows: \(captures.count)")
        for (index, capture) in captures.enumerated() {
            let pixels = capture.pixels.map { "\(Self.text($0)) px" } ?? "no capture"
            let aspect = capture.frame.height > 0 ? Self.text(capture.frame.width / capture.frame.height) : "—"
            lines.append("  #\(index + 1) window \(Self.text(capture.frame)) aspect \(aspect) → \(pixels)")
        }
        let text = lines.joined(separator: "\n")
        report = text
        Self.logger.info("\(text, privacy: .public)")
    }

    private static func text(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private static func text(_ size: CGSize) -> String {
        "\(text(size.width))×\(text(size.height))"
    }

    private static func text(_ rect: CGRect) -> String {
        "\(text(rect.size)) @ (\(text(rect.origin.x)), \(text(rect.origin.y)))"
    }
}

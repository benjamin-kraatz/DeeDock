#if DEBUG
import AppKit

/// Deterministic sample data for App Health labelling previews: no running apps, no timers that fire, no writes.
enum AppHealthLabellingPreviewData {
    static let app = AppHealthAppDisplay(bundleID: "com.example.Studio", name: "Studio",
                                         icon: NSImage(systemSymbolName: "film.stack", accessibilityDescription: nil))
    static let longNamedApp = AppHealthAppDisplay(
        bundleID: "com.example.Verwaltung", name: "Dokumentenverwaltung und Archivierungswerkzeug Professional",
        icon: NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil))

    /// A question whose timers never fire, put into `phase`.
    static func session(app: AppHealthAppDisplay = app, reason: String?,
                        source: AppHealthLabelSource = .prompt,
                        phase: AppHealthLabelSession.Phase = .asking) -> AppHealthLabelSession {
        let session = AppHealthLabelSession(app: app, reason: reason, source: source,
                                            timing: source == .prompt ? .prompt : .manual,
                                            now: { Date(timeIntervalSince1970: 1_793_000_000) },
                                            sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        switch phase {
        case .asking: break
        case .followUp: session.answer(.misbehaving)
        case .thanks: session.answer(.expected)
        }
        return session
    }

    static func reason(_ reasons: [AppHealthPromptReason], trigger: AppHealthPromptTrigger = .rule) -> String {
        AppHealthReasonText.line(trigger: trigger, reasons: reasons, evidence: AppHealthSuspicionEvidence(
            meanCPUPercent: 142, shortWindowSeconds: 180, memoryGrowth: 1_250_000_000, longWindowSeconds: 600,
            meanWakeupsPerSecond: 612))
    }

    static let pickerEntries: [AppHealthPickerEntry] = {
        let apps: [(String, String, String, Double, UInt64)] = [
            ("com.example.Studio", "Studio", "film.stack", 28.4, 2_400_000_000),
            ("com.example.Compiler", "Compiler", "hammer", 19.1, 1_100_000_000),
            ("com.example.Browser", "Browser", "globe", 6.2, 3_800_000_000),
            ("com.example.Mail", "Mail", "envelope", 1.4, 420_000_000),
            ("com.example.Notes", "Notes", "note.text", 0.6, 180_000_000),
            ("com.example.Music", "Music", "music.note", 0.4, 260_000_000),
            ("com.example.Photos", "Photos", "photo", 0.3, 640_000_000),
            ("com.example.Calendar", "Calendar", "calendar", 0.2, 120_000_000),
            ("com.example.Terminal", "Terminal", "terminal", 0.1, 90_000_000),
            ("com.example.Maps", "Maps", "map", 0.1, 210_000_000),
            ("com.example.Weather", "Weather", "cloud.sun", 0, 70_000_000),
            ("com.example.Books", "Books", "book", 0, 110_000_000),
        ]
        return apps.map { id, name, symbol, cpu, mem in
            AppHealthPickerEntry(
                sample: AppHealthSample(app: id, kind: .regular, timestamp: Date(timeIntervalSince1970: 1_793_000_000),
                                        interval: 20, cpuMain: cpu * 20 / 100, cpuHelpers: 0, mem: mem, memMain: mem,
                                        procs: 1, wakeups: 0, energy: nil, frontmost: false),
                display: AppHealthAppDisplay(bundleID: id, name: name,
                                             icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)))
        }
    }()
}
#endif

import Foundation
import Testing
@testable import DeeDock

struct LineIconCoverageTests {
    private let drawn: Set<String> = ["com.apple.Safari", "com.tinyspeck.slackmacgap"]
    private let publicApps = AnalyticsPublicApps(
        catalogedIdentifiers: ["com.tinyspeck.slackmacgap", "com.example.cataloged"],
        isAppStoreInstall: { $0.path.hasPrefix("/Applications/Store") })

    private func app(_ identifier: String?, _ path: String) -> ApplicationReference {
        ApplicationReference(bundleIdentifier: identifier, url: URL(fileURLWithPath: path), name: "App")
    }

    private func coverage(installed: [ApplicationReference], pinned: [ApplicationReference] = []) -> LineIconCoverage {
        LineIconCoverage(installed: installed, pinned: pinned,
                         hasGlyph: { drawn.contains($0.bundleIdentifier ?? "") }, publicApps: publicApps)
    }

    @Test("Only public apps are named; private ones are counted")
    func publicAppsOnly() {
        let result = coverage(installed: [
            app("com.apple.Safari", "/Applications/Safari.app"),
            app("com.example.cataloged", "/Applications/Cataloged.app"),
            app("com.example.store", "/Applications/Store App.app"),
            app("com.apple.Notes", "/System/Applications/Notes.app"),
            app("com.apple.internal-tool", "/Applications/Internal.app"),
            app("com.acme.inhouse", "/Applications/Inhouse.app"),
            app(nil, "/Applications/Unsigned.app"),
        ])
        #expect(result.missing.map(\.bundleIdentifier)
                == ["com.apple.Notes", "com.example.cataloged", "com.example.store"])
        #expect(result.unlistedMissingCount == 3)
        #expect(result.installedCount == 7)
        #expect(result.installedWithGlyphCount == 1)
    }

    @Test("Pins are counted once across displays and flagged when missing")
    func pinnedApps() {
        let slack = app("com.tinyspeck.slackmacgap", "/Applications/Slack.app")
        let cataloged = app("com.example.cataloged", "/Applications/Cataloged.app")
        let result = coverage(installed: [slack, cataloged], pinned: [slack, cataloged, cataloged])
        #expect(result.pinnedCount == 2)
        #expect(result.pinnedWithGlyphCount == 1)
        #expect(result.pinnedCoverage == 0.5)
        #expect(result.missing.map(\.bundleIdentifier) == ["com.example.cataloged"])
        #expect(result.missingPinned.map(\.bundleIdentifier) == ["com.example.cataloged"])
    }

    @Test("A pinned app outside the scan still reports as missing")
    func pinnedOnly() {
        let result = coverage(installed: [], pinned: [app("com.example.cataloged", "/Volumes/Apps/Cataloged.app")])
        #expect(result.installedCoverage == 0)
        #expect(result.missing.map(\.bundleIdentifier) == ["com.example.cataloged"])
        #expect(result.missingPinned.count == 1)
    }

    @Test("Reports wait six hours, unless the clock went backwards")
    func interval() {
        let last = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(LineIconCoverageReporter.isDue(lastReport: nil, now: last))
        #expect(!LineIconCoverageReporter.isDue(lastReport: last, now: last.addingTimeInterval(5 * 60 * 60)))
        #expect(LineIconCoverageReporter.isDue(lastReport: last, now: last.addingTimeInterval(6 * 60 * 60)))
        #expect(LineIconCoverageReporter.isDue(lastReport: last, now: last.addingTimeInterval(-60)))
    }
}

import Foundation
import Testing
@testable import DeeDock

/// The hold-to-delete fill over time.
struct VaporHoldProgressTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func holdingFillsInPointNineSeconds() {
        var hold = VaporHoldProgress()
        #expect(hold.progress(at: start) == 0)
        #expect(!hold.isAnimating(at: start))
        hold.press(at: start)
        #expect(abs(hold.progress(at: start.addingTimeInterval(0.45)) - 0.5) < 1e-9)
        #expect(hold.isAnimating(at: start.addingTimeInterval(0.45)))
        #expect(!hold.isComplete(at: start.addingTimeInterval(0.89)))
        #expect(hold.isComplete(at: start.addingTimeInterval(0.9)))
        #expect(hold.progress(at: start.addingTimeInterval(5)) == 1)
        #expect(!hold.isAnimating(at: start.addingTimeInterval(5)))
    }

    @Test func releasingEarlyDrainsBackAndAPressResumesFromThere() {
        var hold = VaporHoldProgress()
        hold.press(at: start)
        let release = start.addingTimeInterval(0.6)
        hold.release(at: release)
        let atRelease = hold.progress(at: release)
        #expect(abs(atRelease - 0.6 / 0.9) < 1e-9)
        #expect(!hold.isComplete(at: release.addingTimeInterval(1)))
        let drained = release.addingTimeInterval(0.1)
        #expect(abs(hold.progress(at: drained) - (atRelease - 0.1 / VaporHoldProgress.drainDuration)) < 1e-9)
        #expect(hold.isAnimating(at: drained))
        #expect(hold.progress(at: release.addingTimeInterval(1)) == 0)
        #expect(!hold.isAnimating(at: release.addingTimeInterval(1)))
        // Pressing again mid-drain continues from the current fill.
        var again = VaporHoldProgress()
        again.press(at: start)
        again.release(at: start.addingTimeInterval(0.45))
        let repress = start.addingTimeInterval(0.5)
        let value = again.progress(at: repress)
        again.press(at: repress)
        #expect(abs(again.remainingHold(at: repress) - (1 - value) * 0.9) < 1e-9)
        again.reset()
        #expect(again.progress(at: repress) == 0 && !again.isHolding)
    }
}

/// Finder script results, permission status mapping and the children scan.
struct VaporFinderTests {
    @Test func scriptResultsParseToFolderURLs() {
        #expect(VaporFinderScriptResult.folderURL(from: "file:///Users/test/dev/dokk-web/")?.path == "/Users/test/dev/dokk-web")
        #expect(VaporFinderScriptResult.folderURL(from: "file:///Users/test/My%20Projects/")?.path == "/Users/test/My Projects")
        #expect(VaporFinderScriptResult.folderURL(from: "") == nil)
        #expect(VaporFinderScriptResult.folderURL(from: nil) == nil)
        #expect(VaporFinderScriptResult.folderURL(from: "https://example.com/") == nil)
        #expect(VaporFinderScriptResult.folderURL(from: "not a url") == nil)
    }

    @Test func permissionStatusesMap() {
        #expect(VaporAutomationPermission(status: noErr) == .granted)
        #expect(VaporAutomationPermission(status: OSStatus(errAEEventWouldRequireUserConsent)) == .undetermined)
        #expect(VaporAutomationPermission(status: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(VaporAutomationPermission(status: OSStatus(procNotFound)) == .unavailable)
    }

    @Test func scanKeepsOnlySuggestedDirectChildren() throws {
        let temp = try VaporTempDirectory("vapor-scan")
        let home = temp.url.appendingPathComponent("home")
        let project = try temp.folder("dokk-web")
        for name in ["node_modules", ".next", "coverage", "dist", "src", "target", ".turbo"] { try temp.folder("dokk-web/\(name)") }
        try temp.folder("dokk-web/node_modules/nested/.next")
        try temp.folder("dokk-web/Helper.app/Contents")
        try temp.file("dokk-web/build")
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("__pycache__"),
                                                   withDestinationURL: project.appendingPathComponent("src"))
        let names = VaporSuggestionScanner.scan(project, home: home).map(\.name)
        // dist is tagged but never suggested; target lacks Cargo.toml; links, files and packages are skipped.
        #expect(names == [".next", ".turbo", "coverage", "node_modules"])
        try temp.file("dokk-web/Cargo.toml")
        #expect(VaporSuggestionScanner.scan(project, home: home).map(\.name).contains("target"))
        #expect(VaporSuggestionScanner.scan(temp.url.appendingPathComponent("missing"), home: home).isEmpty)
    }

    @Test func measuringCountsFilesAndAllocatedBytes() throws {
        let temp = try VaporTempDirectory("vapor-measure")
        let folder = try temp.folder("node_modules")
        for index in 0..<5 { try temp.file("node_modules/p\(index)/index.js", bytes: 10_000) }
        guard case .measured(let bytes, let files) = VaporFileMeasurer.measureSynchronously(folder) else {
            Issue.record("not measured")
            return
        }
        #expect(files == 5)
        #expect(bytes >= 50_000)
        #expect(VaporFileMeasurer.measureSynchronously(temp.url.appendingPathComponent("missing")) == .unreadable)
    }
}

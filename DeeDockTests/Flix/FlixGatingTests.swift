import AppKit
import Foundation
import Testing
@testable import DeeDock

/// The sensitive question is asked for every drag of a flagged file, whichever app is in front,
/// and the tile does no work while Flix Files is off.
@MainActor @Suite(.serialized)
struct FlixGatingTests {
    @Test func aFlaggedFileIsAskedAboutEvenWithFinderInFront() async throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FlixGating-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A key file is flagged by its name alone.
        let key = folder.appending(path: "server.pem")
        try Data("-----BEGIN PRIVATE KEY-----".utf8).write(to: key)
        let item = FlixItem(path: key.path, name: "server.pem", kind: .document, activity: .downloaded, date: .now,
                            contentTypeIdentifier: "public.x509-certificate")

        let sensitive = FlixSensitiveGuard(folder: nil)
        sensitive.setEnabled(true)
        sensitive.update(items: [item], policy: FlixReadPolicy(home: "/FlixGatingHome", allowedRoots: []))
        for _ in 0..<100 where sensitive.verdict(for: item) == nil { try await Task.sleep(for: .milliseconds(30)) }
        #expect(sensitive.verdict(for: item) == .secret)

        let interceptor = FlixDragInterceptor(conversions: FlixConversionStore(folder: folder.appending(path: "c")),
                                              sensitive: sensitive)
        interceptor.settings = { FlixSettings() }
        let finder = FlixFrontmostContext(processIdentifier: getpid(), bundleIdentifier: "com.apple.finder",
                                          applicationName: "Finder", windowID: nil, windowTitle: nil, capturedAt: .now)
        // The drop could still land in a browser or a chat, so the question comes, without naming Finder.
        #expect(interceptor.confirmation(for: [item], context: finder)
                == .sensitive(itemID: item.id, reason: nil, destination: nil))
        #expect(interceptor.confirmation(for: [item], context: nil) != nil)
        // Not Sensitive stops the asking for that file.
        sensitive.markNotSensitive(item)
        #expect(interceptor.confirmation(for: [item], context: finder) == nil)
    }

    @Test func theTileDoesNothingWhileFlixFilesIsOff() {
        let store = FlixSettingsStore(repository: nil)
        let history = FlixHistory(folder: nil)
        let coordinator = FlixCoordinator(settings: store, history: history)
        let link = FlixLink(url: URL(string: "https://example.com/page")!, title: "Page", browserBundleIdentifier: nil)
        history.record(FlixActivityEvent(link: link, name: "Page", kind: .link, activity: .link, date: .now))
        coordinator.refreshTile()
        #expect(coordinator.tile.newest?.link == link)

        store.settings.isEnabled = false
        coordinator.refreshTile()
        #expect(coordinator.tile.newest == nil && coordinator.tile.thumbnail == nil && coordinator.tile.unseenCount == 0)

        // Back on, the tile loads the newest item afresh.
        store.settings.isEnabled = true
        coordinator.refreshTile()
        #expect(coordinator.tile.newest?.link == link)
    }
}

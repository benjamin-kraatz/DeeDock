import Foundation
import Testing
@testable import DeeDock

/// Which folder each app identity keeps Lookout's data in (`LookoutPaths.standard(forBundleIdentifier:)`): the app and
/// its services agree, and the Debug and Release apps never share an index or a model.
struct LookoutPathsTests {
    private let support = URL(fileURLWithPath: "/Users/tester/Library/Application Support", isDirectory: true)

    private func folder(_ identifier: String?) -> String {
        LookoutPaths.standard(forBundleIdentifier: identifier, applicationSupport: support).base.path
    }

    @Test("Release keeps DDock/Lookout; its services use the same folder", arguments: [
        "de.benjaminkraatz.DeeDock",
        "de.benjaminkraatz.DeeDock.LookoutIndexService",
        "de.benjaminkraatz.DeeDock.LookoutQueryService",
    ])
    func release(identifier: String) {
        #expect(folder(identifier) == support.path + "/DDock/Lookout")
    }

    @Test("The Debug app and its services get DDock/Lookout-dev", arguments: [
        "de.benjaminkraatz.DeeDock.dev",
        "de.benjaminkraatz.DeeDock.dev.LookoutIndexService",
        "de.benjaminkraatz.DeeDock.dev.LookoutQueryService",
    ])
    func debug(identifier: String) {
        #expect(folder(identifier) == support.path + "/DDock/Lookout-dev")
    }

    @Test func otherIdentitiesGetAFolderOfTheirOwn() {
        #expect(folder("com.example.Fork") == support.path + "/DDock/Lookout-com-example-Fork")
        #expect(folder("de.benjaminkraatz.DeeDock.beta/x") == support.path + "/DDock/Lookout-beta-x")
        #expect(LookoutPaths.folderName(forApp: "de.benjaminkraatz.DeeDock.") == "Lookout-unknown")
        // Only a whole suffix is a service's: an app named like one keeps its name.
        #expect(LookoutPaths.appIdentifier(fromBundleIdentifier: ".LookoutQueryService") == ".LookoutQueryService")
        #expect(folder(nil) == support.path + "/DDock/Lookout", "a command-line tool")
    }

    @Test func anInjectedBaseIsUsedAsIs() {
        let base = URL(fileURLWithPath: "/tmp/lookout-paths-test", isDirectory: true)
        let paths = LookoutPaths(base: base)
        #expect(paths.index == base && paths.models.path == "/tmp/lookout-paths-test/Models")
        #expect(paths.partialDownloads.path == "/tmp/lookout-paths-test/Partial")
        #expect(paths.indexFile.path == "/tmp/lookout-paths-test/" + IndexStore.mainFile)
    }
}

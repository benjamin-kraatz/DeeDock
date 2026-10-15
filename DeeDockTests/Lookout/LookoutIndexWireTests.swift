import Foundation
import Testing
@testable import DeeDock

/// What crosses the index service's connection: the app and the service must decode what the other encodes.
struct LookoutIndexWireTests {
    @Test func aConfigurationRoundTripsAndNeverIndexesTheDisk() throws {
        let configuration = LookoutIndexConfiguration(
            roots: ["/", "/Users/tester/Documents"], excludedFolders: ["/Users/tester/Documents/Archive"],
            excludedExtensions: [".HEIC", "txt"], modelsFolder: "/models", indexFolder: "/index", backfillAllowed: true)
        let decoded = try LookoutIndexConfiguration.decode(try configuration.encoded())
        #expect(decoded == configuration)
        #expect(decoded.allowedRoots.map(\.path) == ["/Users/tester/Documents"])
        #expect(decoded.options.excludedExtensions == ["heic", "txt"])
        #expect(decoded.options.excludedFolders == ["/Users/tester/Documents/Archive"])
    }

    @Test func aStatusRoundTripsWithItsActivity() throws {
        var status = LookoutIndexStatus()
        status.activity = .failed(message: "the model can't be loaded")
        status.done = 3
        status.total = 9
        status.counts.byKindAndState = ["image": ["done": 2, "pending": 1], "pdf": ["partial": 1]]
        status.counts.vectors = 40
        status.notPermittedRoots = ["/Users/tester/Desktop"]
        status.vectorsChangedAt = Date(timeIntervalSince1970: 1_800_000_000)
        status.current = .init(kind: .screenshot, name: "Screenshot.png")
        let decoded = try LookoutIndexStatus.decode(try status.encoded())
        #expect(decoded == status)
        #expect(decoded.counts.files == 4 && decoded.counts.searchable == 3 && decoded.counts.pending == 1)
    }
}

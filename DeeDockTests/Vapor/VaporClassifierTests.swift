import Foundation
import Testing
@testable import DeeDock

/// The recognized-folder table from docs/VAPOR.md, including the rules that need a sibling marker.
struct VaporClassifierTests {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let noMarkers: (URL) -> Bool = { _ in false }

    @Test(arguments: [
        ("node_modules", VaporTag.npmPackages), (".next", .nextBuild), (".nuxt", .nuxtBuild),
        (".svelte-kit", .svelteKitBuild), (".turbo", .turborepoCache), (".parcel-cache", .parcelCache),
        ("coverage", .testCoverage), ("DerivedData", .xcodeBuildCache), ("ModuleCache.noindex", .xcodeModuleCache),
        (".gradle", .gradleCache), ("__pycache__", .pythonCache), (".pytest_cache", .pythonCache),
        (".mypy_cache", .pythonCache), (".ruff_cache", .pythonCache), ("dist", .buildOutput), ("build", .buildOutput),
        ("out", .buildOutput),
    ])
    func namesAloneAreRecognized(name: String, tag: VaporTag) {
        let url = home.appendingPathComponent("dev/app/\(name)")
        #expect(VaporClassifier.tag(for: url, home: home, fileExists: noMarkers) == tag)
    }

    @Test func buildOutputIsTaggedButNeverSuggested() {
        #expect(!VaporTag.buildOutput.isSuggested)
        #expect(VaporTag.allCases.filter { !$0.isSuggested } == [.buildOutput])
    }

    @Test func markerRulesNeedTheSiblingFile() throws {
        let temp = try VaporTempDirectory("vapor-classifier")
        let swift = try temp.folder("swift/.build")
        let cargo = try temp.folder("rust/target")
        let pods = try temp.folder("ios/Pods")
        #expect(VaporClassifier.tag(for: swift, home: home) == nil)
        #expect(VaporClassifier.tag(for: cargo, home: home) == nil)
        #expect(VaporClassifier.tag(for: pods, home: home) == nil)
        try temp.file("swift/Package.swift")
        try temp.file("rust/Cargo.toml")
        try temp.file("ios/Podfile")
        #expect(VaporClassifier.tag(for: swift, home: home) == .swiftPMBuild)
        #expect(VaporClassifier.tag(for: cargo, home: home) == .cargoBuild)
        #expect(VaporClassifier.tag(for: pods, home: home) == .cocoaPods)
        // A marker for another rule doesn't count.
        let target = try temp.folder("swift/target")
        #expect(VaporClassifier.tag(for: target, home: home) == nil)
    }

    @Test func childrenOfDerivedDataAreBuildData() {
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        #expect(VaporClassifier.tag(for: derived, home: home, fileExists: noMarkers) == .xcodeBuildCache)
        #expect(VaporClassifier.tag(for: derived.appendingPathComponent("DOKK-abcdefghij"), home: home,
                                    fileExists: noMarkers) == .xcodeBuildData)
        let projectOwn = home.appendingPathComponent("dev/app/DerivedData/App-xyz")
        #expect(VaporClassifier.tag(for: projectOwn, home: home, fileExists: noMarkers) == .xcodeBuildData)
        // Deeper descendants are not recognized by that rule.
        #expect(VaporClassifier.tag(for: derived.appendingPathComponent("DOKK-abc/Build"), home: home,
                                    fileExists: noMarkers) == nil)
    }

    @Test func swiftPMCacheAndItsChildren() {
        let cache = home.appendingPathComponent("Library/Caches/org.swift.swiftpm")
        #expect(VaporClassifier.tag(for: cache, home: home, fileExists: noMarkers) == .swiftPMCache)
        #expect(VaporClassifier.tag(for: cache.appendingPathComponent("repositories"), home: home,
                                    fileExists: noMarkers) == .swiftPMCache)
        let elsewhere = URL(fileURLWithPath: "/Users/other/Library/Caches/org.swift.swiftpm")
        #expect(VaporClassifier.tag(for: elsewhere, home: home, fileExists: noMarkers) == nil)
    }

    @Test func otherFoldersAreUnknownAndNamesAreCaseSensitive() {
        for name in ["src", "Node_Modules", "Coverage", "cache", "derived_data"] {
            #expect(VaporClassifier.classify(home.appendingPathComponent("dev/\(name)"), home: home,
                                             fileExists: noMarkers) == .unknown, "\(name)")
        }
    }
}

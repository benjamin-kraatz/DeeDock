import Foundation
import Testing
@testable import DeeDock

struct LauncherSuggestionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func context(_ foreground: String = "source", date: Date? = nil) -> LauncherSuggestionContext {
        LauncherSuggestionContext(date: date ?? now, foregroundID: foreground, modeID: "work", hour: 10, weekday: 2)
    }

    @Test("Expiry removes old outcomes, old captured contexts, and future records")
    func retention() {
        let expired = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        var document = LauncherSuggestionDocument()
        document.examples = [
            .init(context: context(), targetID: "keep", date: now),
            .init(context: context(date: expired), targetID: "old-context", date: now),
            .init(context: context(), targetID: "old-target", date: expired),
            .init(context: context(), targetID: "future", date: now.addingTimeInterval(1))
        ]
        let changed = document.expire(now: now)
        #expect(changed)
        #expect(document.examples.map(\.targetID) == ["keep"])
        let changedAgain = document.expire(now: now)
        #expect(!changedAgain)
    }

    @Test("Contextual rejection does not exclude the app in another foreground context")
    func contextualFeedback() {
        let examples = [LauncherSuggestionExample(context: context(), targetID: "target", date: now)]
        let rejection = LauncherSuggestionFeedback(date: now, appID: "target", kind: .notNow,
                                                   context: context(), modelVersion: LauncherSuggestionBaseline.version)
        let same = LauncherSuggestionBaseline.scores(context: context(), examples: examples,
            feedback: [rejection], excluded: [], now: now)
        let other = LauncherSuggestionBaseline.scores(context: context("other"), examples: examples,
            feedback: [rejection], excluded: [], now: now)
        #expect(same["target"] == nil)
        #expect(other["target"] != nil)
    }

    @Test("Explicit exclusion and current foreground override useful feedback")
    func exclusions() {
        let feedback = ["excluded", "source"].map {
            LauncherSuggestionFeedback(date: now, appID: $0, kind: .useful,
                context: context(), modelVersion: LauncherSuggestionBaseline.version)
        }
        let scores = LauncherSuggestionBaseline.scores(context: context(), examples: [],
            feedback: feedback, excluded: ["excluded"], now: now)
        #expect(scores.isEmpty)
    }

    @Test("Expired examples and feedback never contribute to the baseline")
    func expiredBaseline() {
        let expired = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        let example = LauncherSuggestionExample(context: context(date: expired), targetID: "old", date: expired)
        let feedback = LauncherSuggestionFeedback(date: expired, appID: "old", kind: .useful,
            context: context(date: expired), modelVersion: LauncherSuggestionBaseline.version)
        #expect(LauncherSuggestionBaseline.scores(context: context(), examples: [example],
            feedback: [feedback], excluded: [], now: now).isEmpty)
    }

    @Test("Repository rejects writes submitted before reset, including after reload")
    func resetSequence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LauncherSuggestionsRepository(directory: directory)
        var populated = LauncherSuggestionDocument()
        populated.examples = [.init(context: context(), targetID: "target", date: now)]
        try await repository.save(populated, sequence: 1)
        try await repository.save(LauncherSuggestionDocument(), sequence: 3)
        try await repository.save(populated, sequence: 2)
        let restarted = LauncherSuggestionsRepository(directory: directory)
        let loaded = try await restarted.load()
        #expect(loaded.examples.isEmpty)
    }

    @Test("Corrupt storage remains intact for diagnosis")
    func corruption() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history-v1.json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: file)
        let repository = LauncherSuggestionsRepository(directory: directory)
        await #expect(throws: (any Error).self) { try await repository.load() }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test("Oversized history saves a bounded document that reloads successfully")
    func boundedPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LauncherSuggestionsRepository(directory: directory)
        var captured = context()
        captured.runningIDs = (0..<40).map { "app.\($0)." + String(repeating: "x", count: 58) }
        var document = LauncherSuggestionDocument()
        document.examples = (0..<7_000).map { _ in
            LauncherSuggestionExample(context: captured, targetID: "target", date: now)
        }
        let originalSize = try JSONEncoder().encode(document).count
        #expect(originalSize > 16 * 1024 * 1024)
        let retained = try await repository.save(document, sequence: 1)
        let loaded = try await repository.load()
        #expect(!loaded.examples.isEmpty)
        #expect(loaded.examples.count == retained.examples.count)
        #expect(loaded.examples.count < document.examples.count)
        let file = directory.appendingPathComponent("history-v1.json")
        let bytes = try Data(contentsOf: file).count
        #expect(bytes <= 16 * 1024 * 1024)
    }

    @Test("Cyclic time keeps midnight adjacent in the fixed feature encoding")
    func featureGeometry() {
        var midnight = context()
        midnight.hour = 0
        var evening = midnight
        evening.hour = 23
        var noon = midnight
        noon.hour = 12
        func distance(_ left: [Float], _ right: [Float]) -> Float {
            zip(left, right).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        }
        #expect(distance(midnight.featureVector, evening.featureVector) < distance(midnight.featureVector, noon.featureVector))
        #expect(midnight.featureVector.count == 256)
        let finite = midnight.featureVector.allSatisfy { $0.isFinite }
        #expect(finite)
    }
}

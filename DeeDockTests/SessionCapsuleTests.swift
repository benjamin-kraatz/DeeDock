import Foundation
import Testing

@MainActor
struct SessionCapsuleTests {
    @Test("Approved capsule text and window identities round trip without capture content")
    func persistence() throws {
        let suite = "SessionCapsules.Persistence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = SessionCapsuleRepository(defaults: defaults)
        let capsule = SessionCapsule(
            title: "Continue invoices",
            summary: "September invoices are reconciled through the latest bank export.",
            unfinishedTasks: ["Resolve the unmatched payment"],
            windows: [.init(applicationName: "Numbers", bundleIdentifier: "com.apple.Numbers",
                            windowTitle: "September Invoices")],
            note: "Ask about the credit note."
        )

        try repository.save(SessionCapsuleDocument(capsules: [capsule]))
        let storedCapsules = try repository.load()
        let loaded = try #require(storedCapsules)
        #expect(loaded.capsules == [capsule])
        let encoded = try #require(defaults.data(forKey: "dock.session-capsules.v1"))
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.localizedCaseInsensitiveContains("screenshot"))
        #expect(!text.localizedCaseInsensitiveContains("recognizedText"))
    }

    @Test("Malformed or future capsule documents are rejected without replacing saved bytes")
    func validation() throws {
        let suite = "SessionCapsules.Validation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "dock.session-capsules.v1"
        let future = Data(#"{"version":99,"capsules":[]}"#.utf8)
        defaults.set(future, forKey: key)
        let repository = SessionCapsuleRepository(defaults: defaults)

        #expect(throws: (any Error).self) { try repository.load() }
        #expect(defaults.data(forKey: key) == future)
    }

    @Test("A draft trims editable content before becoming a saved capsule")
    func draftApproval() {
        let draft = SessionCapsuleDraft(
            title: "  Continue DeeDock  ", summary: "  Review the capsule flow. \n",
            unfinishedTasks: ["  Check VoiceOver  ", "   "],
            windows: [.init(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                            windowTitle: "DeeDock")], note: "  Use two displays.  "
        )

        let capsule = draft.capsule()
        #expect(capsule.title == "Continue DeeDock")
        #expect(capsule.summary == "Review the capsule flow.")
        #expect(capsule.unfinishedTasks == ["Check VoiceOver"])
        #expect(capsule.note == "Use two displays.")
    }
}

import Foundation
import Testing
@testable import DeeDock

@MainActor
struct BadgeAttentionTests {
    private let mail = "/Applications/Mail.app"
    private let messages = "/System/Applications/Messages.app"

    private func store(_ suite: String) throws -> (BadgeAttentionStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (BadgeAttentionStore(defaults: defaults), defaults)
    }

    @Test("Only a higher count, or a different label, is news after acknowledging")
    func rule() {
        #expect(BadgeAttention.isNew(label: "3", acknowledged: nil))
        #expect(!BadgeAttention.isNew(label: nil, acknowledged: nil))
        #expect(!BadgeAttention.isNew(label: "3", acknowledged: "3"))
        #expect(!BadgeAttention.isNew(label: "2", acknowledged: "3"))
        #expect(BadgeAttention.isNew(label: "4", acknowledged: "3"))
        #expect(!BadgeAttention.isNew(label: "•", acknowledged: "•"))
        #expect(BadgeAttention.isNew(label: "!", acknowledged: "•"))
    }

    @Test("Acknowledging quiets a badge until its count rises, and survives a relaunch")
    func acknowledgePersists() throws {
        let (attention, defaults) = try store("BadgeAttentionTests.acknowledge")
        attention.acknowledge(key: mail, label: "5", via: .dockClick)
        #expect(!attention.isNew(key: mail, label: "5"))
        #expect(attention.isNew(key: mail, label: "6"))
        #expect(attention.isNew(key: messages, label: "1"))
        #expect(!BadgeAttentionStore(defaults: defaults).isNew(key: mail, label: "5"))
    }

    @Test("A cleared badge forgets its acknowledgement; an unknown one keeps it")
    func clearedForgets() throws {
        let (attention, _) = try store("BadgeAttentionTests.cleared")
        attention.acknowledge(key: mail, label: "•", via: .dockClick)
        attention.acknowledge(key: messages, label: "2", via: .activation)
        attention.reconcile([mail: .unknown, messages: .cleared], frontmost: nil)
        #expect(!attention.isNew(key: mail, label: "•"))
        #expect(attention.isNew(key: messages, label: "2"))
    }

    @Test("A falling count lowers the acknowledgement, so the next rise is news")
    func fallingCountLowers() throws {
        let (attention, _) = try store("BadgeAttentionTests.falling")
        attention.acknowledge(key: mail, label: "5", via: .dockClick)
        attention.reconcile([mail: .count(3)], frontmost: nil)
        #expect(attention.isNew(key: mail, label: "4"))
    }

    @Test("A badge arriving on the frontmost app is acknowledged at once")
    func frontmostAcknowledges() throws {
        let (attention, _) = try store("BadgeAttentionTests.frontmost")
        attention.reconcile([mail: .count(2), messages: .count(1)], frontmost: mail)
        #expect(!attention.isNew(key: mail, label: "2"))
        #expect(attention.isNew(key: messages, label: "1"))
    }
}

import Foundation
import Testing
@testable import DeeDock

/// What the uninstall sheet selects, only offers, or leaves out. A wrong "selected" moves someone's data
/// to the Trash, so these pin the rules down.
struct AppLeftoverRulesTests {
    private let library = URL(fileURLWithPath: "/Users/test/Library")

    private func rules(identifiers: [String] = ["com.example.Editor"], helpers: [String] = [], groups: [String] = [],
                       names: [String] = ["Editor"], others: [AppLeftoverRules.OtherApp] = []) -> AppLeftoverRules {
        AppLeftoverRules(identity: .init(identifiers: identifiers, helperIdentifiers: helpers, appGroups: groups, names: names),
                         others: others)
    }

    private func root(_ path: String, _ kind: AppLeftover.Kind, _ naming: AppLeftoverRoot.Naming,
                      names: Bool = false, domain: AppLeftover.Domain = .user) -> AppLeftoverRoot {
        AppLeftoverRoot(url: library.appendingPathComponent(path), kind: kind, domain: domain, naming: naming,
                        allowsNameMatches: names)
    }

    private func names(_ items: [AppLeftover]) -> [String] { items.map { $0.url.lastPathComponent } }
    private func kinds(_ items: [AppLeftover]) -> [AppLeftover.Kind] { items.map { $0.kind } }

    @Test func exactIdentifiersAreSelected() {
        let rules = rules(identifiers: ["com.example.Editor", "com.example.Editor.Widget"])
        let found = rules.leftovers(in: root("Containers", .container, .bundle),
                                    entries: ["com.example.Editor", "com.example.Editor.Widget", "com.other.App"])
        #expect(names(found) == ["com.example.Editor", "com.example.Editor.Widget"])
        #expect(kinds(found) == [.container, .extensionContainer])
        #expect(found.allSatisfy { $0.selectedByDefault })
    }

    @Test func extensionsAreStrippedBeforeMatching() {
        let found = rules().leftovers(in: root("Preferences", .preferences, .bundle),
                                      entries: ["com.example.Editor.plist", "com.example.Editor.lockfile", "com.example.Editorial.plist"])
        #expect(names(found) == ["com.example.Editor.plist", "com.example.Editor.lockfile"])
    }

    @Test func helperAndUpdaterSuffixesAreTheAppsOwn() {
        let found = rules().leftovers(in: root("Caches", .caches, .bundle),
                                      entries: ["com.example.Editor.ShipIt", "com.example.Editor.helper"])
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.match == .bundleIdentifier })
    }

    @Test func byHostPreferencesMatchTheirHardwareUUID() {
        let found = rules().leftovers(in: root("Preferences/ByHost", .preferences, .bundle),
                                      entries: ["com.example.Editor.0F6A8B2C-1D3E-4F50-8A9B-0C1D2E3F4A5B.plist"])
        #expect(found.first?.match == .bundleIdentifier)
    }

    @Test func otherSuffixesAreOnlyOffered() {
        // A sibling product of the same developer may have left this, not the app being removed.
        let found = rules().leftovers(in: root("Caches", .caches, .bundle), entries: ["com.example.Editor.canary"])
        #expect(found.first?.match == .similarName)
        #expect(found.first?.selectedByDefault == false)
    }

    @Test func aMoreSpecificInstalledAppOwnsItsData() {
        let pro = AppLeftoverRules.OtherApp(bundleIdentifier: "com.example.Editor.Pro", name: "Editor Pro", appGroups: [])
        let found = rules(others: [pro]).leftovers(in: root("Application Support", .applicationSupport, .bundle),
                                                   entries: ["com.example.Editor.Pro", "com.example.Editor"])
        #expect(names(found) == ["com.example.Editor"])
    }

    @Test func anotherCopyWithTheSameIdentifierSharesTheData() {
        let copy = AppLeftoverRules.OtherApp(bundleIdentifier: "com.example.Editor", name: "Editor Copy", appGroups: [])
        let found = rules(others: [copy]).leftovers(in: root("Containers", .container, .bundle), entries: ["com.example.Editor"])
        #expect(found.first?.sharedWith == "Editor Copy")
        #expect(found.first?.selectedByDefault == false)
    }

    @Test func anotherCopysExtensionAndHelperDataIsShared() {
        let copy = AppLeftoverRules.OtherApp(bundleIdentifier: "com.example.Editor", name: "Editor (~/Applications)",
                                             appGroups: [], otherIdentifiers: ["com.example.Editor.Widget", "com.example.EditorHelper"])
        let rules = rules(identifiers: ["com.example.Editor", "com.example.Editor.Widget"], helpers: ["com.example.EditorHelper"],
                          others: [copy])
        let containers = rules.leftovers(in: root("Containers", .container, .bundle), entries: ["com.example.Editor.Widget"])
        let helpers = rules.leftovers(in: root("PrivilegedHelperTools", .backgroundHelper, .helper, domain: .allUsers),
                                      entries: ["com.example.EditorHelper"])
        #expect(containers.first?.sharedWith == "Editor (~/Applications)")
        #expect(helpers.first?.sharedWith == "Editor (~/Applications)")
        #expect(containers.allSatisfy { !$0.selectedByDefault } && helpers.allSatisfy { !$0.selectedByDefault })
        #expect(containers.count == 1 && helpers.count == 1)
    }

    @Test func appGroupsAreSelectedUnlessAnotherAppUsesThem() {
        let word = AppLeftoverRules.OtherApp(bundleIdentifier: "com.example.Word", name: "Word", appGroups: ["TEAM.Office"])
        let found = rules(groups: ["TEAM.Office", "TEAM.Editor"], others: [word])
            .leftovers(in: root("Group Containers", .groupContainer, .group), entries: ["TEAM.Office", "TEAM.Editor", "TEAM.Other"])
        #expect(names(found) == ["TEAM.Office", "TEAM.Editor"])
        #expect(found[0].sharedWith == "Word")
        #expect(found[0].selectedByDefault == false)
        #expect(found[1].selectedByDefault)
    }

    @Test func nameMatchesAreOnlyOfferedWhereAllowed() {
        let rules = rules()
        let support = rules.leftovers(in: root("Application Support", .applicationSupport, .bundle, names: true),
                                      entries: ["Editor", "editor", "Editorial"])
        #expect(support.count == 2)
        #expect(support.allSatisfy { $0.match == .similarName && !$0.selectedByDefault })
        let containers = rules.leftovers(in: root("Containers", .container, .bundle), entries: ["Editor"])
        #expect(containers.isEmpty)
    }

    @Test func nameMatchesSkipNamesOfOtherInstalledApps() {
        let other = AppLeftoverRules.OtherApp(bundleIdentifier: "com.other.Editor", name: "Editor", appGroups: [])
        let found = rules(others: [other]).leftovers(in: root("Caches", .caches, .bundle, names: true), entries: ["Editor"])
        #expect(found.isEmpty)
    }

    @Test func broadIdentifiersAndGenericNamesNeverMatch() {
        let rules = rules(identifiers: ["Code"], names: ["Data", "Code"])
        #expect(rules.identity.identifiers.isEmpty)
        #expect(rules.identity.names == ["Code"])
        // "Code" is still worth offering by name (Visual Studio Code keeps its data there); "Data" is not.
        let found = rules.leftovers(in: root("Caches", .caches, .bundle, names: true), entries: ["Data", "Code"])
        #expect(names(found) == ["Code"])
        #expect(found.first?.match == .similarName)
    }

    @Test func homeDotFoldersMatchTheLowercasedName() {
        let home = AppLeftoverRoot(url: URL(fileURLWithPath: "/Users/test"), kind: .homeFolder, domain: .user,
                                   naming: .bundle, allowsNameMatches: true)
        let found = rules(names: ["Big Editor"]).leftovers(in: home, entries: [".bigeditor", ".ssh", "Documents"])
        #expect(names(found) == [".bigeditor"])
        #expect(found.first?.match == .similarName)
    }

    @Test func launchdJobsMatchHelperIdentifiers() {
        let found = rules(helpers: ["com.example.EditorHelperTool"])
            .leftovers(in: root("LaunchDaemons", .backgroundHelper, .launchd, domain: .allUsers),
                       entries: ["com.example.EditorHelperTool.plist", "com.example.Editor.update.plist", "com.vendor.other.plist"])
        #expect(names(found) == ["com.example.EditorHelperTool.plist", "com.example.Editor.update.plist"])
        #expect(found.allSatisfy { $0.keepsRunning && $0.domain == .allUsers })
    }

    @Test func protectedItemsAreNeverSelected() {
        var item = AppLeftover(url: library.appendingPathComponent("Containers/com.example.Editor"), kind: .container,
                               match: .bundleIdentifier, domain: .user)
        item.isProtected = true
        #expect(item.selectedByDefault == false)
    }
}

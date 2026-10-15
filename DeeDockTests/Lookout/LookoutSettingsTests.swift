import Foundation
import Testing
@testable import DeeDock

/// Lookout's settings persist as JSON under `hub.lookout.v1`, in a throwaway defaults suite here.
struct LookoutSettingsTests {
    private let suite = "dokk.tests.lookout.\(UUID().uuidString)"

    private func repository() -> (LookoutSettingsRepository, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (LookoutSettingsRepository(defaults: defaults), defaults)
    }

    @Test func nothingSavedMeansLookoutIsOff() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = try repository.load()
        #expect(settings == LookoutSettings())
        #expect(!settings.enabled && !settings.setupCompleted && !settings.isActive && settings.indexOnBattery)
    }

    @Test func settingsRoundTrip() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = LookoutSettings()
        settings.enabled = true
        settings.setupCompleted = true
        settings.folders = ["/Users/x/Documents", "/Users/x/Downloads"]
        settings.excludedFolders = ["/Users/x/Downloads/Media"]
        settings.excludedExtensions = ["heic", ".txt"]
        settings.indexOnBattery = false
        try repository.save(settings)
        #expect(defaults.data(forKey: LookoutSettingsRepository.key) != nil)
        #expect(LookoutSettingsRepository.key == "hub.lookout.v1")
        #expect(try repository.load() == settings)
    }

    @Test func missingKeysTakeTheirDefaults() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"enabled":true,"folders":["/a"]}"#.utf8), forKey: LookoutSettingsRepository.key)
        let settings = try repository.load()
        #expect(settings.enabled && settings.folders == ["/a"])
        #expect(!settings.setupCompleted && settings.indexOnBattery && settings.excludedFolders.isEmpty)
    }

    @Test func unreadableDataLeavesLookoutOff() {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not data", forKey: LookoutSettingsRepository.key)
        #expect(throws: (any Error).self) { try repository.load() }
        defaults.set(Data("{".utf8), forKey: LookoutSettingsRepository.key)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(repository.loadOrDefault() == LookoutSettings())
    }

    @Test func theAnalyticsSummaryHoldsNoPaths() {
        var settings = LookoutSettings()
        settings.enabled = true
        settings.folders = ["/Users/x/Documents", "/Users/x/Documents/Taxes", "/Users/x/Downloads"]
        settings.excludedFolders = ["/Users/x/Downloads/Media", "/elsewhere"]
        settings.excludedExtensions = ["heic, .TXT"]
        let summary = settings.analyticsSafe
        #expect(summary == .init(enabled: true, setupCompleted: false, folderCount: 2, excludedFolderCount: 1,
                                 excludedExtensionCount: 2, indexOnBattery: true))
    }
}

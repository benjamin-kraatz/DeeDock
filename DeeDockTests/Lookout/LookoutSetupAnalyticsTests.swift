import Foundation
import Testing
@testable import DeeDock

/// Lookout's Settings section and the analytics of onboarding, the download and Settings: closed tokens and counts,
/// never a folder, a path or a file name.
@MainActor
struct LookoutSetupAnalyticsTests {
    private func values(_ event: AnalyticsEvent) -> [String: String] {
        event.properties.values.mapValues(\.displayText)
    }

    @Test("Lookout is a feature section of its own, reported as lookout")
    func settingsSection() {
        let section = SettingsSection.lookout
        #expect(SettingsSection.featureSections.contains(section))
        #expect(SettingsSection.fixed.contains(section))
        #expect(section.id == "lookout")
        #expect(section.pageGroups.isEmpty && !section.offersRestoreDefaults)
        #expect(section.glyph == .lookout)
        #expect(section.title?.key == "lookoutSettingsTitle")
        #expect(section.matches("Lookout"))
        #expect(AnalyticsSettingsSection(section).rawValue == "lookout")
        let viewed = AnalyticsEvent.settingsViewed(AnalyticsSettingsSection(section), page: nil, via: .request,
                                                   display: nil)
        #expect(values(viewed)["section"] == "lookout")
    }

    @Test("Onboarding steps report their tokens")
    func steps() {
        #expect(LookoutSetupStep.allCases.map(\.analytics.rawValue)
            == ["welcome", "folders", "access", "download", "first_pass"])
        let viewed = AnalyticsEvent.lookoutSetupStepViewed(.access)
        #expect(viewed.name == "lookout_setup_step_viewed" && values(viewed) == ["step": "access"])
        let abandoned = AnalyticsEvent.lookoutSetupAbandoned(lastStep: .download)
        #expect(abandoned.name == "lookout_setup_abandoned" && values(abandoned) == ["last_step": "download"])
    }

    @Test("Setup completed reports counts and the battery choice only")
    func completed() {
        let event = AnalyticsEvent.lookoutSetupCompleted(folderCount: 4, allowedCount: 3, skippedCount: 1,
                                                         estimatedFiles: 5_202, indexOnBattery: false)
        #expect(event.name == "lookout_setup_completed")
        #expect(values(event) == ["folder_count": "4", "allowed_count": "3", "skipped_count": "1",
                                  "estimated_files": "5202", "index_on_battery": "false"])
    }

    @Test("The download reports its outcome, seconds and an error category")
    func download() {
        let failed = AnalyticsEvent.lookoutModelDownload(outcome: .failed, seconds: 42,
                                                         error: LookoutDownloadError.checksumMismatch.analyticsCategory)
        #expect(failed.name == "lookout_model_download")
        #expect(values(failed) == ["outcome": "failed", "seconds": "42", "error": "checksum"])
        let done = AnalyticsEvent.lookoutModelDownload(outcome: .completed, seconds: 300, error: nil)
        #expect(values(done) == ["outcome": "completed", "seconds": "300"])
        let categories: [LookoutDownloadError] = [.notEnoughSpace(needed: 1, available: 0), .network(code: -1009),
                                                  .server(status: 503), .unexpectedHost, .checksumMismatch,
                                                  .incomplete, .write(reason: "/Users/tester/secret")]
        #expect(categories.map(\.analyticsCategory.rawValue)
            == ["disk_space", "network", "server", "host", "checksum", "incomplete", "write"])
    }

    @Test("Access results carry the answer and where it was asked, never the folder")
    func access() {
        let event = AnalyticsEvent.lookoutAccessResult(.denied, context: .settings)
        #expect(event.name == "lookout_access_result")
        #expect(values(event) == ["outcome": "denied", "context": "settings"])
    }

    @Test("Settings changes use setting_changed keys, and Settings can open onboarding through the Hub")
    func settingKeys() {
        #expect(AnalyticsFeatureSetting.lookoutEnabled.rawValue == "lookout_enabled")
        #expect(AnalyticsFeatureSetting.lookoutIndexOnBattery.rawValue == "lookout_index_on_battery")
        #expect(AnalyticsFeatureSetting.lookoutFolderCount.rawValue == "lookout_folder_count")
        #expect(AnalyticsHubTrigger.lookoutSetup.rawValue == "lookout_setup")
    }

    @Test("Before setup, the switch opens onboarding instead of turning Lookout on")
    func switchBeforeSetup() {
        let model = LookoutSettingsModel(engine: .inert(), setup: nil, inspector: LookoutStubFolderInspector(),
                                         picker: LookoutStubFolderPicker(), home: "/Users/tester")
        var opened = 0
        model.presentSetup = { opened += 1 }
        model.setOn(true)
        #expect(opened == 1 && !model.isOn && model.engine.settings == LookoutSettings())
    }

    @Test("Settings adds a picked folder only when it may be read, and refuses the home folder")
    func settingsAddsFolders() async {
        var settings = LookoutSettings.activeForTests
        settings.folders = ["/Users/tester/Documents"]
        let picker = LookoutStubFolderPicker()
        let model = LookoutSettingsModel(
            engine: .inert(settings: settings), setup: nil,
            inspector: LookoutStubFolderInspector(accessByPath: ["/Users/tester/Private": .denied]), picker: picker,
            home: "/Users/tester")
        picker.next = URL(fileURLWithPath: "/Users/tester")
        await model.addFolder()
        #expect(model.notice == .refused(.homeFolder) && model.folders == ["/Users/tester/Documents"])
        picker.next = URL(fileURLWithPath: "/Users/tester/Private")
        await model.addFolder()
        #expect(model.notice == .notAllowed && model.folders == ["/Users/tester/Documents"])
        picker.next = URL(fileURLWithPath: "/Users/tester/Work")
        await model.addFolder()
        #expect(model.notice == nil && model.folders == ["/Users/tester/Documents", "/Users/tester/Work"])
        model.removeFolder("/Users/tester/Documents")
        #expect(model.folders == ["/Users/tester/Work"])
    }
}

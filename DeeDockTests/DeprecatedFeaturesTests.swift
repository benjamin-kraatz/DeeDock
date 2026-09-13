import Foundation
import Testing
@testable import DeeDock

@MainActor
struct DeprecatedFeaturesTests {
    @Test("Deprecated Features pages sit in the last group; soap bubbles stays active")
    func featuresOverviewGroups() throws {
        let groups = SettingsSection.features.pageGroups
        let last = try #require(groups.last)
        #expect(last == SettingsPage.deprecatedPages)
        #expect(Set(last) == [
            .sims, .focusBreathing, .focusDebt, .pinWeather, .quarantine, .patchBay
        ])
        let active = Set(groups.dropLast().flatMap(\.self))
        #expect(active.contains(.soapBubbles))
        #expect(active.contains(.focusSessions))
        #expect(active.contains(.shelfAndTrash))
        #expect(active.contains(.discovery))
        #expect(active.contains(.clipboardMuseum))
        #expect(active.contains(.appSuggestions))
        #expect(active.contains(.magneticEdges))
        #expect(!active.contains(.sims))
        #expect(!active.contains(.patchBay))
        #expect(!SettingsPage.focusSessions.isDeprecated)
        #expect(!SettingsPage.soapBubbles.isDeprecated)
        #expect(SettingsPage.deprecatedPages.allSatisfy(\.isDeprecated))
    }

    @Test("Pin weather starts off for new documents and missing keys")
    func pinWeatherDefaultsOff() {
        #expect(PinWeatherDocument().enabled == false)
        let decoded = try? JSONDecoder().decode(PinWeatherDocument.self, from: Data("{}".utf8))
        #expect(decoded?.enabled == false)
    }

    @Test("Retirement turns persisted enable flags off")
    func forceOffPersists() throws {
        let suffix = UUID().uuidString
        let simsDefaults = try #require(UserDefaults(suiteName: "DeprecatedSims.\(suffix)"))
        let breathingDefaults = try #require(UserDefaults(suiteName: "DeprecatedBreathing.\(suffix)"))
        let focusDefaults = try #require(UserDefaults(suiteName: "DeprecatedFocus.\(suffix)"))
        let weatherDefaults = try #require(UserDefaults(suiteName: "DeprecatedWeather.\(suffix)"))
        let patchDefaults = try #require(UserDefaults(suiteName: "DeprecatedPatch.\(suffix)"))
        defer {
            simsDefaults.removePersistentDomain(forName: "DeprecatedSims.\(suffix)")
            breathingDefaults.removePersistentDomain(forName: "DeprecatedBreathing.\(suffix)")
            focusDefaults.removePersistentDomain(forName: "DeprecatedFocus.\(suffix)")
            weatherDefaults.removePersistentDomain(forName: "DeprecatedWeather.\(suffix)")
            patchDefaults.removePersistentDomain(forName: "DeprecatedPatch.\(suffix)")
        }

        let sims = DockSimsStore(repository: DockSimsRepository(defaults: simsDefaults))
        sims.start()
        sims.setEnabled(true)
        #expect(sims.isEnabled)

        let breathing = FocusBreathingStore(defaults: breathingDefaults)
        breathing.setEnabled(true)
        #expect(breathing.enabled)

        let focus = FocusSessionController(defaults: focusDefaults)
        focus.start()
        focus.configureFocusDebt(enabled: true)
        #expect(focus.focusDebt.enabled)

        let weather = PinWeatherStore(repository: PinWeatherRepository(defaults: weatherDefaults))
        weather.start()
        weather.setEnabled(true)
        #expect(weather.enabled)

        var patchDocument = PatchBayDocument()
        patchDocument.enabled = true
        try PatchBayRepository(defaults: patchDefaults).save(patchDocument)
        let patchBay = PatchBayController(
            profiles: DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil),
            repository: PatchBayRepository(defaults: patchDefaults)
        )
        #expect(patchBay.document.enabled)

        let quarantineWasEnabled = QuarantineStampController.shared.enabled
        QuarantineStampController.shared.enabled = true
        defer { QuarantineStampController.shared.enabled = quarantineWasEnabled }

        DeprecatedFeaturesRetirement.disableEnabledFlags(
            sims: sims,
            focusBreathing: breathing,
            focusSession: focus,
            pinWeather: weather,
            quarantine: .shared,
            patchBay: patchBay
        )

        #expect(!sims.isEnabled)
        #expect(!breathing.enabled)
        #expect(!focus.focusDebt.enabled)
        #expect(!weather.enabled)
        #expect(!patchBay.document.enabled)
        #expect(!QuarantineStampController.shared.enabled)

        let reloadedSims = DockSimsStore(repository: DockSimsRepository(defaults: simsDefaults))
        reloadedSims.start()
        #expect(!reloadedSims.isEnabled)

        let reloadedBreathing = FocusBreathingStore(defaults: breathingDefaults)
        #expect(!reloadedBreathing.enabled)

        let reloadedFocus = FocusSessionController(defaults: focusDefaults)
        reloadedFocus.start()
        #expect(!reloadedFocus.focusDebt.enabled)

        let reloadedWeather = PinWeatherStore(repository: PinWeatherRepository(defaults: weatherDefaults))
        reloadedWeather.start()
        #expect(!reloadedWeather.enabled)

        let reloadedPatch = PatchBayController(
            profiles: DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil),
            repository: PatchBayRepository(defaults: patchDefaults)
        )
        #expect(!reloadedPatch.document.enabled)
    }
}

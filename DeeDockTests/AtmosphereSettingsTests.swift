import Foundation
import Testing
@testable import DeeDock

@MainActor
struct AtmosphereSettingsTests {
    @Test("Documents saved before intensity keep other fields and use the midpoint default")
    func missingIntensityDecodesAsDefault() throws {
        var settings = AtmosphereSettings()
        settings.enabled = true
        settings.density = 0.8
        settings.preset = .focus
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        object.removeValue(forKey: "intensity")
        let decoded = try JSONDecoder().decode(
            AtmosphereSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.enabled)
        #expect(decoded.density == 0.8)
        #expect(decoded.preset == .focus)
        #expect(decoded.intensity == AtmosphereLimits.defaultIntensity)
    }

    @Test("Intensity persists and reloads through the Atmosphere store")
    func storePersistsIntensity() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AtmosphereStore(defaults: defaults)
        store.settings.intensity = 0.85
        #expect(store.settings.intensity == 0.85)
        let reloaded = AtmosphereStore(defaults: defaults)
        #expect(reloaded.settings.intensity == 0.85)
        #expect(reloaded.settings.enabled == false)
    }

    @Test("Out-of-range and non-finite intensity snap to the slider bounds on load")
    func storeClampsIntensity() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var high = AtmosphereSettings()
        high.intensity = 4
        defaults.set(try JSONEncoder().encode(high), forKey: "atmosphere.settings.v1")
        #expect(AtmosphereStore(defaults: defaults).settings.intensity == 1)

        var low = AtmosphereSettings()
        low.intensity = -2
        defaults.set(try JSONEncoder().encode(low), forKey: "atmosphere.settings.v1")
        #expect(AtmosphereStore(defaults: defaults).settings.intensity == 0)

        #expect(AtmosphereLimits.clamped(.nan) == AtmosphereLimits.defaultIntensity)
        #expect(AtmosphereLimits.clamped(.infinity) == AtmosphereLimits.defaultIntensity)
    }

    @Test("Default intensity keeps the original Atmosphere wash")
    func defaultMatchesOriginalWash() {
        #expect(AtmosphereLimits.ambientOpacity(preset: .focus, intensity: 0.5) == 0.18)
        #expect(AtmosphereLimits.ambientOpacity(preset: .minimal, intensity: 0.5) == 0.07)
        #expect(AtmosphereLimits.rimWidth(intensity: 0.5) == 2)
    }

    @Test("Intensity endpoints stay visible and avoid a full-screen wash")
    func endpointsStayInAtmosphereRange() {
        #expect(AtmosphereLimits.ambientOpacity(preset: .party, intensity: 0) == 0.18 * 0.30)
        #expect(AtmosphereLimits.ambientOpacity(preset: .party, intensity: 1) == 0.18 * 2.20)
        #expect(AtmosphereLimits.ambientOpacity(preset: .minimal, intensity: 0) == 0.07 * 0.30)
        #expect(AtmosphereLimits.ambientOpacity(preset: .minimal, intensity: 1) == 0.07 * 2.20)
        #expect(AtmosphereLimits.rimWidth(intensity: 0) == 1)
        #expect(AtmosphereLimits.rimWidth(intensity: 1) == 3)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "DeeDockAtmosphereTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}

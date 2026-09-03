import Foundation
import Testing

@MainActor struct DockEdgeSettingsTests {
    private let legacy = Data(#"{"iconSize":48,"magnification":1.4,"alignment":"right","horizontalOffset":-72,"bottomDistance":35,"positionReference":"usableDesktop","behavior":{"autoHide":true,"activationLocation":"screenEdge","widthMode":"custom","customWidth":450,"zoneHeight":12,"zoneOffset":80,"revealDelay":0.1,"hideDelay":0.4,"animationStyle":"leftFade","animationDuration":0.2}}"#.utf8)

    @Test("Existing settings load as bottom placement and retain the original encoded names")
    func legacyCompatibility() throws {
        var settings = try JSONDecoder().decode(DockSettings.self, from: legacy)
        #expect(settings.edge == .bottom)
        #expect(settings.alignment == .end)
        #expect(settings.alongEdgeOffset == -72)
        #expect(settings.edgeDistance == 35)
        #expect(settings.itemSpacing == 4)
        #expect(settings.behavior.lengthMode == .custom)
        #expect(settings.behavior.customLength == 450)
        #expect(settings.behavior.zoneDepth == 12)
        for edge in DockEdge.allCases {
            settings.edge = edge
            let data = try JSONEncoder().encode(settings)
            #expect(try JSONDecoder().decode(DockSettings.self, from: data) == settings)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["alignment"] as? String == "right")
            #expect(object["horizontalOffset"] as? Double == -72)
            #expect(object["bottomDistance"] as? Double == 35)
            #expect(object["alongEdgeOffset"] == nil)
            let behavior = try #require(object["behavior"] as? [String: Any])
            #expect(behavior["widthMode"] as? String == "custom")
            #expect(behavior["customWidth"] as? Double == 450)
            #expect(behavior["zoneHeight"] as? Double == 12)
        }
    }

    @Test("Top uses usable desktop while preserving shared and per-display reference requests")
    func topReference() throws {
        var settings = DockSettings(edge: .top, positionReference: .screenEdge)
        #expect(settings.positionReference.resolved(for: settings.edge) == .usableDesktop)
        settings = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.edge == .top && settings.positionReference == .screenEdge)
        for edge in [DockEdge.bottom, .left, .right] {
            settings.edge = edge
            #expect(settings.positionReference.resolved(for: settings.edge) == .screenEdge)
        }

        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let display = DisplayFixtures.screen("top", runtimeID: 1, primary: true)
        profiles.synchronize([display]) { [] }
        defaults.update(\.positionReference, to: .screenEdge)
        profiles.update(display.id, keyPath: \.edge, to: .top)
        let inherited = profiles.effectiveSettings(for: display.id)
        #expect(inherited.positionReference == .screenEdge)
        #expect(inherited.positionReference.resolved(for: inherited.edge) == .usableDesktop)
        #expect(profiles.document.profiles[display.id]?.overrides.positionReference == nil)

        profiles.update(display.id, keyPath: \.positionReference, to: .screenEdge)
        defaults.update(\.positionReference, to: .usableDesktop)
        profiles.update(display.id, keyPath: \.edge, to: .bottom)
        #expect(profiles.effectiveSettings(for: display.id).positionReference == .screenEdge)
        profiles.update(display.id, keyPath: \.edge, to: .top)
        profiles.useDefault(.positionReference, for: display.id)
        defaults.update(\.positionReference, to: .screenEdge)
        profiles.useDefault(.edge, for: display.id)
        #expect(profiles.effectiveSettings(for: display.id).edge == .bottom)
        #expect(profiles.effectiveSettings(for: display.id).positionReference == .screenEdge)
    }

    @Test("Malformed edge values refuse loading without replacing saved bytes")
    func invalidEdges() throws {
        let suite = "DeeDockEdges.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = DockSettingsRepository(defaults: defaults)
        var object = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        for value in ["diagonal" as Any, 4, NSNull()] {
            object["edge"] = value
            let data = try JSONSerialization.data(withJSONObject: object)
            defaults.set(data, forKey: "dock.settings.v1")
            #expect(throws: (any Error).self) { try repository.load() }
            #expect(defaults.data(forKey: "dock.settings.v1") == data)
            let overrides = try JSONSerialization.data(withJSONObject: ["edge": value])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(DockSettingsOverrides.self, from: overrides) }
        }
    }

    @Test("Per-display edge inheritance and resets preserve pins, spacing, visibility, and placement requests")
    func inheritance() throws {
        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let display = DisplayFixtures.screen("edge", runtimeID: 1, primary: true)
        let pins = [DisplayFixtures.app("a"), DisplayFixtures.app("b")]
        profiles.synchronize([display]) { pins }
        profiles.update(display.id, keyPath: \.alongEdgeOffset, to: 50)
        profiles.update(display.id, keyPath: \.edgeDistance, to: 35)
        profiles.update(display.id, keyPath: \.itemSpacing, to: 12)
        profiles.setEnabled(false, for: display.id)
        defaults.update(\.edge, to: .left)
        #expect(profiles.effectiveSettings(for: display.id).edge == .left)
        profiles.update(display.id, keyPath: \.edge, to: .left)
        defaults.update(\.edge, to: .right)
        #expect(profiles.effectiveSettings(for: display.id).edge == .left)
        profiles.useDefault(.edge, for: display.id)
        #expect(profiles.effectiveSettings(for: display.id).edge == .right)
        let settings = profiles.effectiveSettings(for: display.id)
        #expect(settings.alongEdgeOffset == 50 && settings.edgeDistance == 35 && settings.itemSpacing == 12)
        profiles.synchronize([]) { [] }
        profiles.synchronize([display]) { [] }
        #expect(profiles.effectiveSettings(for: display.id) == settings)
        profiles.useDefaults(for: display.id)
        #expect(profiles.pinLists[display.id] == pins.map(DockPin.application))
        #expect(profiles.document.profiles[display.id]?.enabled == false)
        let old = try JSONDecoder().decode(DockSettingsOverrides.self,
            from: Data(#"{"alignment":"left","horizontalOffset":42,"bottomDistance":12,"widthMode":"dockWidth"}"#.utf8))
        #expect(old.edge == nil)
        #expect(old.resolving(defaults.value).edge == .right)
        #expect(old.alignment == .start && old.alongEdgeOffset == 42 && old.edgeDistance == 12)
    }
}

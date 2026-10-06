import Foundation
import Testing
@testable import DeeDock

@MainActor struct LineIconTests {
    @Test("Generated path data becomes a path, and anything else is rejected")
    func pathParsing() {
        let drawn = LineIconPath.parse("M2 2L22 2L22 22Z")
        #expect(drawn != nil)
        #expect(!drawn!.isEmpty)
        #expect(LineIconPath.parse("M2 2 22 22") != nil)
        #expect(LineIconPath.parse("M2 2C4 4 8 8 10 10") != nil)
        #expect(LineIconPath.parse("") == nil)
        #expect(LineIconPath.parse("M2 2") == nil)
        #expect(LineIconPath.parse("Q1 1 2 2") == nil)
        #expect(LineIconPath.parse("L2 2") == nil)
        #expect(LineIconPath.parse("M2 2L") == nil)
    }

    @Test("Lookups prefer the bundle identifier, then the app name, and miss cleanly")
    func catalogLookup() {
        let json = """
        {"glyphs":{"lucide:mark":{"stroke":["M2 2L22 22"]},"broken":{"stroke":["nope"]}},\
        "bundleIdentifiers":{"com.example.Known":"lucide:mark"},"appNames":{"named":"lucide:mark","broken":"broken"},\
        "tiles":{"trash":"lucide:mark","folder":"missing"}}
        """.replacingOccurrences(of: "\\", with: "")
        let catalog = LineIconCatalog { Data(json.utf8) }
        let known = URL(fileURLWithPath: "/Applications/Other.app")
        #expect(catalog.glyph(bundleIdentifier: "com.example.Known", url: known)?.id == "lucide:mark")
        let named = URL(fileURLWithPath: "/Applications/Named.app")
        #expect(catalog.glyph(bundleIdentifier: nil, url: named)?.stroke != nil)
        #expect(catalog.glyph(bundleIdentifier: "com.example.Missing", url: known) == nil)
        #expect(catalog.glyph(bundleIdentifier: nil, url: URL(fileURLWithPath: "/Applications/Broken.app")) == nil)
        #expect(catalog.glyph(for: .trash)?.id == "lucide:mark")
        #expect(catalog.glyph(for: .folder) == nil)
        #expect(catalog.glyph(bundleIdentifier: "com.example.Known", url: known)?.id == "lucide:mark")
    }

    @Test("A document saved before icon style existed stays on native artwork")
    func iconStylePersistence() throws {
        var settings = DockSettings.defaults
        settings.iconStyle = .line
        let encoded = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DockSettings.self, from: encoded).iconStyle == .line)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(DockSettings.defaults)) as? [String: Any])
        object.removeValue(forKey: "iconStyle")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DockSettings.self, from: legacy).iconStyle == .native)
        var overrides = DockSettingsOverrides()
        #expect(overrides.resolving(.defaults).iconStyle == .native)
        overrides.iconStyle = .line
        #expect(overrides.resolving(.defaults).iconStyle == .line)
    }
}

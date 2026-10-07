import Foundation
import Testing
@testable import DeeDock

@MainActor
struct DockContextMenuRevealTests {
    @Test("Settings saved before the style existed pop out, and every style round-trips")
    func persistence() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var legacy = try #require(JSONSerialization.jsonObject(with: encoder.encode(DockSettings.defaults)) as? [String: Any])
        legacy.removeValue(forKey: "contextMenuReveal")
        let decoded = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.contextMenuReveal == .popOut)
        for reveal in DockContextMenuReveal.allCases {
            var settings = DockSettings.defaults
            settings.contextMenuReveal = reveal
            #expect(try decoder.decode(DockSettings.self, from: encoder.encode(settings)).contextMenuReveal == reveal)
            #expect(settings.normalized?.contextMenuReveal == reveal)
        }
    }

    @Test("Every display resolves the app-wide style")
    func appWide() {
        var defaults = DockSettings.defaults
        defaults.contextMenuReveal = .slideOut
        #expect(DockSettingsOverrides().resolving(defaults).contextMenuReveal == .slideOut)
        #expect(!DockSettingField.allCases.contains { $0.keyPath == \DockSettings.contextMenuReveal })
    }

    @Test("Reduce Motion never holds the menu back and never leaves the tile under it")
    func reduceMotion() {
        #expect(DockContextMenuReveal.slideOut.effective(reduceMotion: true) == .popOut)
        #expect(DockContextMenuReveal.popOut.effective(reduceMotion: true) == .popOut)
        #expect(DockContextMenuReveal.off.effective(reduceMotion: true) == .off)
        for reveal in DockContextMenuReveal.allCases {
            #expect(reveal.effective(reduceMotion: false) == reveal)
        }
    }
}

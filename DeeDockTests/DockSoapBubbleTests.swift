import Foundation
import Testing
@testable import DeeDock

@MainActor
struct DockSoapBubbleTests {
    @Test("Absent soap-bubble key stays off and an explicit on value round-trips")
    func persistence() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var legacy = try #require(JSONSerialization.jsonObject(with: encoder.encode(DockSettings.defaults)) as? [String: Any])
        legacy.removeValue(forKey: "soapBubbleEffects")
        let decoded = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!decoded.soapBubbleEffects)
        var enabled = DockSettings.defaults
        enabled.soapBubbleEffects = true
        #expect(try decoder.decode(DockSettings.self, from: encoder.encode(enabled)).soapBubbleEffects)
        #expect(enabled.normalized?.soapBubbleEffects == true)
    }

    @Test("Soap-bubble playback stays off unless the preference is on and Reduce Motion is off")
    func playbackGates() {
        let controller = DockSoapBubbleController()
        #expect(!controller.isEnabled)
        controller.play(itemID: "safari", reduceMotion: false)
        #expect(controller.bursts.isEmpty)

        controller.isEnabled = true
        controller.play(itemID: "safari", reduceMotion: true)
        #expect(controller.bursts.isEmpty)

        controller.play(itemID: "safari", reduceMotion: false)
        #expect(controller.bursts.map(\.itemID) == ["safari"])
        controller.play(itemID: "mail", reduceMotion: false)
        controller.play(itemID: "notes", reduceMotion: false)
        controller.play(itemID: "calendar", reduceMotion: false)
        #expect(controller.bursts.count == DockSoapBubbleController.maximumConcurrentBursts)
        #expect(controller.bursts.map(\.itemID) == ["mail", "notes", "calendar"])

        controller.removeAll()
        #expect(controller.bursts.isEmpty)
    }
}

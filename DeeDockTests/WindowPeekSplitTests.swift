import AppKit
import Testing
@testable import DeeDock

@MainActor
struct WindowPeekSplitTests {
    @Test("Split-peek remains off for existing settings and survives an enabled round trip")
    func settingsMigration() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var settings = DockSettings.defaults
        #expect(!settings.windowPeekSplitEnabled)
        settings.windowPeekSplitEnabled = true
        let data = try encoder.encode(settings)
        #expect(try decoder.decode(DockSettings.self, from: data).windowPeekSplitEnabled)
        #expect(DockSettingsOverrides().resolving(settings).windowPeekSplitEnabled)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "windowPeekSplitEnabled")
        let migrated = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!migrated.windowPeekSplitEnabled)
        #expect(!DockSettingsOverrides().resolving(migrated).windowPeekSplitEnabled)
        for preset in WindowPeekPreset.allCases {
            var candidate = migrated
            preset.apply(to: &candidate)
            #expect(!candidate.windowPeekSplitEnabled)
        }
    }

    @Test("Keyboard selection keeps the chosen window in the pair, including the final window")
    func selection() throws {
        let state = try makeState()
        let ids = state.cards.map(\.id)
        #expect(state.splitCards.map(\.id) == Array(ids.prefix(2)))
        state.select(by: 1)
        #expect(state.splitCards.map(\.id) == Array(ids.suffix(2)))
        state.select(by: 1)
        #expect(state.splitCards.map(\.id) == Array(ids.suffix(2)))
        var chosen: ApplicationWindowToken?
        state.choose = { chosen = $0 }
        state.chooseSelection()
        #expect(chosen == ids.last)
        state.select(by: 1)
        #expect(state.selectedID == ids.first)
    }

    @Test("Unavailable captures keep the ordinary cards and selection intact")
    func missingCapture() throws {
        let state = try makeState()
        let selected = state.selectedID
        state.cards[1].thumbnail = nil
        #expect(state.splitCards.isEmpty)
        #expect(state.splitCandidates.count == 2)
        #expect(state.cards.count == 3)
        #expect(state.selectedID == selected)
        state.cards = [state.cards[0]]
        #expect(state.splitCards.isEmpty)
    }

    @Test("Opt-out, file handoff, Show all, and narrow displays suppress split",
          arguments: ["disabled", "handoff", "all", "narrow", "loading"])
    func fallback(_ reason: String) throws {
        let state = try makeState()
        switch reason {
        case "disabled": state.settings.windowPeekSplitEnabled = false
        case "handoff": state.routingFiles = true
        case "all": state.showsAllWindows = true
        case "narrow": state.splitFitsDisplay = false
        default: state.phase = .loading
        }
        #expect(state.splitCards.isEmpty)
        #expect(state.splitCandidates.isEmpty)
        #expect(state.cards.count == 3)
    }

    @Test("Split placement fits two panes and stays on negative-origin displays", arguments: DockEdge.allCases)
    func geometry(_ edge: DockEdge) {
        let visible = CGRect(x: -1400, y: -200, width: 1100, height: 800)
        let anchor = WindowPeekAnchor(icon: CGRect(x: -900, y: 0, width: 48, height: 48),
                                      edge: edge, visibleFrame: visible)
        for layout in WindowPeekLayout.allCases {
            var settings = DockSettings.defaults
            settings.windowPeekLayout = layout
            let placement = WindowPeekGeometry.placement(anchor: anchor, settings: settings, count: 3, split: true)
            #expect(visible.insetBy(dx: 12, dy: 12).contains(placement.frame))
            #expect(placement.frame.width >= WindowPeekGeometry.minimumSplitWidth)
        }
    }

    private func makeState() throws -> WindowPeekState {
        let item = DockItem(reference: ApplicationReference(bundleIdentifier: "test.split",
            url: URL(fileURLWithPath: "/Test/Split.app"), name: "Split"),
            icon: NSImage(size: CGSize(width: 32, height: 32)),
            isFavorite: true, isRunning: true, isAvailable: true)
        var settings = DockSettings.defaults
        settings.windowPeekSplitEnabled = true
        let state = WindowPeekState(item: item, settings: settings)
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let session = UUID()
        state.cards = (0..<3).map { index in
            WindowPeekCard(window: ApplicationWindowSummary(
                token: ApplicationWindowToken(sessionID: session, id: UUID()), processIdentifier: 42,
                title: "Window \(index)", frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                isMinimized: false, isMain: index == 0), thumbnail: image)
        }
        state.phase = .windows
        state.selectedID = state.cards.first?.id
        return state
    }
}

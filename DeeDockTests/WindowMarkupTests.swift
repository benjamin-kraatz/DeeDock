import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct WindowMarkupTests {
    private let size = CGSize(width: 2000, height: 1200)
    private var metrics: WindowMarkupMetrics { WindowMarkupMetrics(documentSize: size) }

    // MARK: - Settings

    @Test("Markup settings default, survive a round trip, and are absent from older saves")
    func settingsMigration() throws {
        var settings = DockSettings.defaults
        #expect(settings.windowMarkupFormat == .png)
        #expect(settings.windowMarkupSearchEngine == .google)
        #expect(settings.windowMarkupFolder == nil)
        settings.windowMarkupFormat = .jpeg
        settings.windowMarkupSearchEngine = .duckDuckGo
        settings.windowMarkupFolder = "/tmp/markups"
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(DockSettings.self, from: data)
        #expect(restored.windowMarkupFormat == .jpeg)
        #expect(restored.windowMarkupSearchEngine == .duckDuckGo)
        #expect(restored.windowMarkupFolder == "/tmp/markups")
        // App-wide: a display override never holds its own value.
        #expect(DockSettingsOverrides().resolving(settings).windowMarkupFolder == "/tmp/markups")
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["windowMarkupFormat", "windowMarkupSearchEngine", "windowMarkupFolder"] { legacy.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.windowMarkupFormat == .png)
        #expect(migrated.windowMarkupFolder == nil)
    }

    @Test("The markup folder defaults under Pictures and honours a configured path")
    func folder() {
        let fallback = WindowMarkupFolder.url(configured: nil)
        #expect(fallback.lastPathComponent == WindowMarkupFolder.defaultName)
        #expect(fallback.path.contains("Pictures"))
        #expect(WindowMarkupFolder.url(configured: "~/Desktop/Shots").path.hasSuffix("/Desktop/Shots"))
        #expect(WindowMarkupFolder.url(configured: "").lastPathComponent == WindowMarkupFolder.defaultName)
    }

    @Test("Search engines build a query URL and refuse an empty query")
    func searchURL() throws {
        for engine in WindowMarkupSearchEngine.allCases {
            let url = try #require(engine.url(for: "  release notes 0.9  "))
            #expect(url.scheme == "https")
            #expect(url.query()?.contains("q=release%20notes%200.9") == true)
            #expect(engine.url(for: "   ") == nil)
        }
    }

    // MARK: - Document

    @Test("Commit, undo, and redo keep the mark list and clear stale selection")
    func undoRedo() {
        let document = WindowMarkupDocument(size: size)
        let mark = WindowMarkupElement(shape: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)), color: .red, weight: .regular)
        document.commit(mark)
        document.selectedID = mark.id
        #expect(document.hasMarks && document.canUndo && !document.canRedo)
        document.undo()
        #expect(!document.hasMarks && document.canRedo)
        #expect(document.selectedID == nil)
        document.redo()
        #expect(document.elements == [mark])
        document.commit(WindowMarkupElement(shape: .badge(number: document.nextBadgeNumber, center: .zero), color: .red, weight: .bold))
        #expect(!document.canRedo)
        #expect(document.nextBadgeNumber == 2)
    }

    @Test("An abandoned text mark leaves neither a mark nor an undo step")
    func emptyText() {
        let document = WindowMarkupDocument(size: size)
        document.beginText(at: CGPoint(x: 40, y: 40))
        #expect(document.editingTextID != nil)
        document.finishText()
        #expect(!document.hasMarks && !document.canUndo)
        document.beginText(at: CGPoint(x: 40, y: 40))
        document.setEditingText("Ship it")
        document.finishText()
        #expect(document.hasMarks && document.canUndo)
        if case .text(let string, _) = document.elements[0].shape { #expect(string == "Ship it") } else { Issue.record("not text") }
    }

    @Test("Reopening a text mark is one undo step; clearing it removes the mark without eating earlier steps")
    func reopenText() {
        let document = WindowMarkupDocument(size: size)
        let box = WindowMarkupElement(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, weight: .regular)
        document.commit(box)
        document.beginText(at: .zero)
        document.setEditingText("Hello")
        document.finishText()
        let textID = document.elements[1].id
        // Unchanged: no extra step.
        document.reopenText(textID)
        document.finishText()
        document.undo()
        #expect(document.elements == [box])
        document.redo()
        // Changed: one step.
        document.reopenText(textID)
        document.setEditingText("Hello again")
        document.finishText()
        document.undo()
        if case .text(let string, _) = document.elements[1].shape { #expect(string == "Hello") } else { Issue.record("not text") }
        // Cleared: the mark goes, the rectangle's own step survives.
        document.reopenText(textID)
        document.setEditingText("")
        document.finishText()
        #expect(document.elements == [box])
        document.undo()
        #expect(document.elements.count == 2)
        document.undo()
        #expect(document.elements == [box])
        document.undo()
        #expect(!document.hasMarks)
    }

    @Test("Moving a mark during one drag records a single undo step")
    func dragIsOneUndoStep() {
        let document = WindowMarkupDocument(size: size)
        let mark = WindowMarkupElement(shape: .badge(number: 1, center: CGPoint(x: 100, y: 100)), color: .blue, weight: .regular)
        document.commit(mark)
        document.update(mark.id, shape: mark.shape.translated(by: CGSize(width: 5, height: 5)))
        document.update(mark.id, shape: mark.shape.translated(by: CGSize(width: 30, height: 10)), continuing: true)
        if case .badge(_, let center) = document.elements[0].shape { #expect(center == CGPoint(x: 130, y: 110)) }
        document.undo()
        #expect(document.elements == [mark])
        document.undo()
        #expect(!document.hasMarks)
    }

    // MARK: - Geometry

    @Test("A single point strokes as a dot and a drag rectangle normalises either corner order")
    func pathsAndRects() {
        #expect(!WindowMarkupGeometry.strokePath([CGPoint(x: 5, y: 5)]).isEmpty)
        #expect(WindowMarkupGeometry.rect(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20))
                == CGRect(x: 10, y: 20, width: 40, height: 40))
        #expect(WindowMarkupGeometry.distance(from: CGPoint(x: 5, y: 5), toSegment: .zero, CGPoint(x: 10, y: 0)) == 5)
        #expect(WindowMarkupGeometry.clampedCrop(CGRect(x: -20, y: -20, width: 100, height: 100), in: size)
                == CGRect(x: 0, y: 0, width: 80, height: 80))
        #expect(WindowMarkupGeometry.clampedCrop(CGRect(x: 0, y: 0, width: 4, height: 400), in: size) == nil)
    }

    @Test("Hit testing grabs a box by its edge, a badge by its area, and the topmost mark wins")
    func hitTesting() {
        let box = WindowMarkupElement(shape: .rectangle(CGRect(x: 100, y: 100, width: 400, height: 300)), color: .red, weight: .regular)
        let badge = WindowMarkupElement(shape: .badge(number: 1, center: CGPoint(x: 300, y: 250)), color: .red, weight: .regular)
        let marks = [box, badge]
        #expect(WindowMarkupGeometry.hit(CGPoint(x: 100, y: 200), in: marks, metrics: metrics) == box.id)
        #expect(WindowMarkupGeometry.hit(CGPoint(x: 200, y: 200), in: marks, metrics: metrics) == nil)
        #expect(WindowMarkupGeometry.hit(CGPoint(x: 305, y: 255), in: marks, metrics: metrics) == badge.id)
        let cover = WindowMarkupElement(shape: .redact(CGRect(x: 250, y: 200, width: 200, height: 100), style: .solid),
                                        color: .black, weight: .regular)
        #expect(WindowMarkupGeometry.hit(CGPoint(x: 305, y: 255), in: marks + [cover], metrics: metrics) == cover.id)
    }

    @Test("Metrics scale with the picture so marks read the same on small and large captures")
    func metricsScale() {
        let small = WindowMarkupMetrics(documentSize: CGSize(width: 400, height: 300))
        let large = WindowMarkupMetrics(documentSize: CGSize(width: 4000, height: 3000))
        #expect(large.penWidth(.regular) > small.penWidth(.regular) * 5)
        #expect(small.penWidth(.bold) > small.penWidth(.thin))
        #expect(small.pixelBlock >= 8)
    }

    // MARK: - Layout

    @Test("The markup window fits the display, respects the minimum, and centres itself")
    func panelFrame() {
        let visible = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let frame = WindowMarkupLayout.panelFrame(documentSize: CGSize(width: 2880, height: 1800), visibleFrame: visible)
        #expect(visible.contains(frame))
        #expect(frame.width >= WindowMarkupLayout.minimumSize.width && frame.height >= WindowMarkupLayout.minimumSize.height)
        #expect(abs(frame.midX - visible.midX) < 1 && abs(frame.midY - visible.midY) < 1)
        let tiny = WindowMarkupLayout.panelFrame(documentSize: CGSize(width: 200, height: 100), visibleFrame: visible)
        #expect(tiny.size.width == WindowMarkupLayout.minimumSize.width)
    }

    @Test("The picture is aspect-fitted and centred in the stage")
    func pictureFrame() {
        let placement = WindowMarkupLayout.pictureFrame(documentSize: CGSize(width: 2000, height: 1000), stage: CGSize(width: 800, height: 800))
        #expect(placement.scale == 0.4)
        #expect(placement.frame == CGRect(x: 0, y: 200, width: 800, height: 400))
        #expect(WindowMarkupComposite.outputSize(documentSize: size, crop: CGRect(x: 0, y: 0, width: 500, height: 400), framed: false)
                == CGSize(width: 500, height: 400))
        let padding = WindowMarkupLayout.framePadding(documentSize: size)
        #expect(WindowMarkupComposite.outputSize(documentSize: size, crop: nil, framed: true)
                == CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding))
    }

    @Test("The document is the window at backing resolution, or the preview when the frame is unknown")
    func documentSize() {
        let token = ApplicationWindowToken(sessionID: UUID(), id: UUID())
        let framed = ApplicationWindowSummary(token: token, processIdentifier: 1, title: "A",
                                              frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isMinimized: false, isMain: true)
        #expect(WindowMarkupSession.documentSize(window: framed, preview: nil, backingScale: 2) == CGSize(width: 2880, height: 1800))
        let unframed = ApplicationWindowSummary(token: token, processIdentifier: 1, title: "A", frame: nil, isMinimized: false, isMain: true)
        #expect(WindowMarkupSession.documentSize(window: unframed, preview: nil, backingScale: 2) == CGSize(width: 1_280, height: 800))
    }

    // MARK: - Export

    @Test("File names keep the title, replace separators, and never collide")
    func filenames() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = WindowMarkupExport.suggestedFilename(title: "Q3/Plan: v2", appName: "Numbers", at: date, format: .jpeg)
        #expect(name.hasPrefix("Q3 Plan v2 "))
        #expect(name.hasSuffix(".jpg"))
        #expect(WindowMarkupExport.suggestedFilename(title: "   ", appName: "Numbers", at: date, format: .png).hasPrefix("Numbers "))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("markup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = WindowMarkupExport.uniqueURL(in: folder, filename: "Shot.png")
        try Data().write(to: first)
        #expect(WindowMarkupExport.uniqueURL(in: folder, filename: "Shot.png").lastPathComponent == "Shot 2.png")
    }

    // MARK: - Enlarged preview hold

    @Test("The pointer holds the hero on it, waits in the corridor, and lets go elsewhere")
    func hold() {
        let peek = CGRect(x: 500, y: 70, width: 520, height: 220)
        let hero = CGRect(x: 300, y: 400, width: 900, height: 500)
        #expect(WindowPeekEnlargeHold.retention(pointer: CGPoint(x: 700, y: 600), hero: hero, peek: peek) == .hero)
        #expect(WindowPeekEnlargeHold.retention(pointer: CGPoint(x: 700, y: 330), hero: hero, peek: peek) == .corridor)
        #expect(WindowPeekEnlargeHold.retention(pointer: CGPoint(x: 100, y: 330), hero: hero, peek: peek) == .none)
        #expect(WindowPeekEnlargeHold.retention(pointer: CGPoint(x: 700, y: 1000), hero: hero, peek: peek) == .none)
        let toolbar = WindowPeekHeroToolbarPanel.frame(forHero: hero)
        #expect(hero.contains(toolbar))
        #expect(toolbar.maxX == hero.maxX - WindowPeekHeroToolbarPanel.inset && toolbar.maxY == hero.maxY - WindowPeekHeroToolbarPanel.inset)
    }

    @Test("Screen and stage conversions are inverses on a display with a negative origin")
    func screenConversion() {
        let container = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let rect = CGRect(x: -1500, y: 100, width: 400, height: 300)
        let local = WindowPeekEnlargeGeometry.local(rect, in: container)
        #expect(WindowPeekEnlargeGeometry.screen(local, in: container) == rect)
    }
}

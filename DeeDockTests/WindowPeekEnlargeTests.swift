import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct WindowPeekEnlargeTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// The same display minus a 38-point menu bar.
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let window = CGSize(width: 1400, height: 900)

    @Test("Enlarged preview stays off for existing settings, presets, and display resolution")
    func settingsMigration() throws {
        var settings = DockSettings.defaults
        #expect(!settings.windowPeekEnlargeEnabled)
        settings.windowPeekEnlargeEnabled = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DockSettings.self, from: data).windowPeekEnlargeEnabled)
        #expect(DockSettingsOverrides().resolving(settings).windowPeekEnlargeEnabled)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "windowPeekEnlargeEnabled")
        let migrated = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!migrated.windowPeekEnlargeEnabled)
        for preset in WindowPeekPreset.allCases {
            var candidate = migrated
            preset.apply(to: &candidate)
            #expect(!candidate.windowPeekEnlargeEnabled)
        }
    }

    @Test("The hero clears the Peek panel and the display margins on every dock edge",
          arguments: DockEdge.allCases)
    func heroClearsPeek(_ edge: DockEdge) throws {
        let peek: CGRect = switch edge {
        case .bottom: CGRect(x: 500, y: 70, width: 520, height: 220)
        case .top: CGRect(x: 500, y: 650, width: 520, height: 220)
        case .left: CGRect(x: 70, y: 300, width: 300, height: 400)
        case .right: CGRect(x: 1140, y: 300, width: 300, height: 400)
        }
        let hero = try #require(WindowPeekEnlargeGeometry.hero(windowSize: window, screenFrame: screen, visibleFrame: visible,
                                                               peekFrame: peek, edge: edge))
        // The placard sits under the image, so the block the Peek panel must clear includes it.
        let block = CGRect(x: hero.minX, y: hero.minY - WindowPeekEnlargeGeometry.placardSpace,
                           width: hero.width, height: hero.height + WindowPeekEnlargeGeometry.placardSpace)
        #expect(!block.intersects(peek.insetBy(dx: -WindowPeekEnlargeGeometry.peekGap + 1,
                                               dy: -WindowPeekEnlargeGeometry.peekGap + 1)))
        #expect(visible.insetBy(dx: WindowPeekEnlargeGeometry.screenMargin - 1,
                                dy: WindowPeekEnlargeGeometry.screenMargin - 1).contains(block))
        #expect(abs(hero.width / hero.height - window.width / window.height) < 0.01)
    }

    @Test("A short Peek panel keeps a large hero exactly centered; a tall one moves it off center")
    func heroCenteringBesidePeek() throws {
        let short = CGRect(x: 500, y: 70, width: 520, height: 60)
        let centered = try #require(WindowPeekEnlargeGeometry.hero(windowSize: window, screenFrame: screen,
                                                                   visibleFrame: visible, peekFrame: short,
                                                                   edge: .bottom))
        #expect(abs(centered.midX - screen.midX) < 1)
        #expect(abs(centered.midY - screen.midY) < 1)
        let tall = CGRect(x: 500, y: 70, width: 520, height: 420)
        let shifted = try #require(WindowPeekEnlargeGeometry.hero(windowSize: window, screenFrame: screen,
                                                                  visibleFrame: visible, peekFrame: tall,
                                                                  edge: .bottom))
        #expect(shifted.midY > screen.midY)
        #expect(shifted.minY - WindowPeekEnlargeGeometry.placardSpace >= tall.maxY + WindowPeekEnlargeGeometry.peekGap)
    }

    @Test("The hero is exactly centered on the display and never exceeds the window's size")
    func heroCenteringAndCap() throws {
        let smallPeek = CGRect(x: 700, y: 70, width: 120, height: 60)
        let small = CGSize(width: 500, height: 320)
        let hero = try #require(WindowPeekEnlargeGeometry.hero(windowSize: small, screenFrame: screen, visibleFrame: visible,
                                                               peekFrame: smallPeek, edge: .bottom))
        #expect(hero.size == small)
        // Centered on the whole display, not the visible frame the menu bar shortens.
        #expect(abs(hero.midX - screen.midX) < 1)
        #expect(abs(hero.midY - screen.midY) < 1)
    }

    @Test("A display without room for a meaningful enlargement stages nothing")
    func heroRefusesCrampedDisplay() {
        let cramped = CGRect(x: 0, y: 0, width: 800, height: 420)
        let peek = CGRect(x: 200, y: 20, width: 400, height: 200)
        #expect(WindowPeekEnlargeGeometry.hero(windowSize: window, screenFrame: cramped, visibleFrame: cramped,
                                               peekFrame: peek, edge: .bottom) == nil)
    }

    @Test("Screen rectangles convert into a stage on a display with negative origins")
    func localConversion() {
        let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let rect = CGRect(x: -1800, y: 600, width: 200, height: 100)
        #expect(WindowPeekEnlargeGeometry.local(rect, in: screen) == CGRect(x: 120, y: 80, width: 200, height: 100))
    }

    @Test("The hi-res budget is the hero in backing pixels")
    func captureBudget() {
        #expect(WindowPeekEnlargeGeometry.capturePixels(hero: CGSize(width: 800, height: 500.2), backingScale: 2)
                == CGSize(width: 1600, height: 1001))
        #expect(WindowPeekEnlargeGeometry.capturePixels(hero: CGSize(width: 800, height: 500), backingScale: 0)
                == CGSize(width: 800, height: 500))
    }

    @Test("The flight starts exactly on the card; Reduce Motion and unknown sources fade in place")
    func flightPoses() throws {
        let image = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let hero = CGRect(x: 200, y: 100, width: 800, height: 500)
        let source = CGRect(x: 520, y: 700, width: 240, height: 150)
        func exhibit(source: CGRect?, reduceMotion: Bool) -> WindowPeekExhibit {
            WindowPeekExhibit(token: ApplicationWindowToken(sessionID: UUID(), id: UUID()), title: "Doc",
                              preview: image, source: source, hero: hero, reduceMotion: reduceMotion)
        }
        let flying = exhibit(source: source, reduceMotion: false).pose
        let start = CGRect(x: hero.minX + flying.offset.width, y: hero.minY + flying.offset.height,
                           width: hero.width * flying.scale.width, height: hero.height * flying.scale.height)
        for (actual, expected) in [(start.minX, source.minX), (start.minY, source.minY),
                                   (start.width, source.width), (start.height, source.height)] {
            #expect(abs(actual - expected) < 0.001)
        }
        #expect(flying.opacity == 1)
        #expect(!exhibit(source: source, reduceMotion: true).morphs)
        #expect(exhibit(source: source, reduceMotion: true).pose.opacity == 0)
        #expect(exhibit(source: nil, reduceMotion: false).pose.opacity == 0)
        let lifted = exhibit(source: source, reduceMotion: false)
        lifted.lifted = true
        #expect(lifted.pose == .settled(hero: hero, scale: 1, opacity: 1))
        lifted.leaving = true
        #expect(lifted.pose.opacity == 0)
    }

    @Test("Quartz window frames convert to AppKit coordinates, including displays above the primary")
    func quartzConversion() {
        let primaryMaxY: CGFloat = 982
        #expect(WindowPeekEnlargeGeometry.appKit(fromQuartz: CGRect(x: 100, y: 50, width: 800, height: 600),
                                                 primaryMaxY: primaryMaxY)
                == CGRect(x: 100, y: 332, width: 800, height: 600))
        #expect(WindowPeekEnlargeGeometry.appKit(fromQuartz: CGRect(x: -1200, y: -900, width: 800, height: 600),
                                                 primaryMaxY: primaryMaxY)
                == CGRect(x: -1200, y: 1282, width: 800, height: 600))
    }

    @Test("A click lands the exhibit exactly on the window frame with window corners")
    func landingPose() throws {
        let image = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let hero = CGRect(x: 200, y: 100, width: 800, height: 500)
        let window = CGRect(x: 40, y: 60, width: 1200, height: 750)
        let exhibit = WindowPeekExhibit(token: ApplicationWindowToken(sessionID: UUID(), id: UUID()), title: "Doc",
                                        preview: image, source: nil, hero: hero, reduceMotion: false)
        exhibit.lifted = true
        exhibit.landing = window
        let pose = exhibit.pose
        let end = CGRect(x: hero.minX + pose.offset.width, y: hero.minY + pose.offset.height,
                         width: hero.width * pose.scale.width, height: hero.height * pose.scale.height)
        for (actual, expected) in [(end.minX, window.minX), (end.minY, window.minY),
                                   (end.width, window.width), (end.height, window.height)] {
            #expect(abs(actual - expected) < 0.001)
        }
        #expect(pose.opacity == 1)
        #expect(abs(pose.cornerRadius * pose.scale.width - WindowPeekExhibitPose.windowCornerRadius) < 0.001)
    }

    @Test("Scrubbing to a neighbor while staged waits less than the first dwell")
    func timing() {
        #expect(WindowPeekEnlargeTiming.dwell(staged: true) < WindowPeekEnlargeTiming.dwell(staged: false))
        #expect(WindowPeekEnlargeTiming.leaveGrace < WindowPeekEnlargeTiming.dwell)
    }
}

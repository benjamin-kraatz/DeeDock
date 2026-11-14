import AppKit
import Foundation
import Testing
@testable import DeeDock

/// `HubThumbnailCache` over an injected renderer: shared renders, results kept when a caller scrolls away, renders
/// cancelled when nobody waits, and the modification date in the key.
@MainActor
struct HubThumbnailCacheTests {
    private let url = URL(fileURLWithPath: "/tmp/hub-thumbnail-tests/picture.png")
    private let size = CGSize(width: 64, height: 64)
    private let probe = ThumbnailRenderProbe()

    private func cache() -> HubThumbnailCache {
        let probe = probe
        return HubThumbnailCache { _, _, _ in
            let delay = await probe.started()
            do {
                try await Task.sleep(for: delay)
            } catch {
                await probe.wasCancelled()
                return nil
            }
            return NSImage(size: NSSize(width: 4, height: 4))
        }
    }

    @Test func callersOfOneKeyShareARenderAndItsResultIsCached() async {
        await probe.setDelay(.milliseconds(50))
        let cache = cache()
        async let first = cache.thumbnail(for: url, size: size, scale: 2)
        async let second = cache.thumbnail(for: url, size: size, scale: 2)
        let (a, b) = await (first, second)
        #expect(a != nil && a === b)
        let again = await cache.thumbnail(for: url, size: size, scale: 2)
        #expect(again === a)
        #expect(await probe.starts == 1)
    }

    /// A cell that scrolls away doesn't throw the render away while another cell still waits for it.
    @Test func aRenderOutlivesACancelledCallerAndStaysCached() async {
        await probe.setDelay(.milliseconds(200))
        let cache = cache()
        let leaving = Task { await cache.thumbnail(for: url, size: size, scale: 2) }
        let staying = Task { await cache.thumbnail(for: url, size: size, scale: 2) }
        #expect(await eventually { await probe.starts == 1 })
        leaving.cancel()
        #expect(await leaving.value == nil)
        let image = await staying.value
        #expect(image != nil)
        #expect(await probe.cancellations == 0)
        #expect(await cache.thumbnail(for: url, size: size, scale: 2) === image)
        #expect(await probe.starts == 1)
    }

    /// A fast scroll leaves no render behind: the last caller to go cancels it, and it caches nothing.
    @Test func theLastCallerLeavingCancelsTheRender() async {
        await probe.setDelay(.seconds(30))
        let cache = cache()
        let leaving = Task { await cache.thumbnail(for: url, size: size, scale: 2) }
        #expect(await eventually { await probe.starts == 1 })
        leaving.cancel()
        #expect(await leaving.value == nil)
        #expect(await eventually { await probe.cancellations == 1 })
        await probe.setDelay(.zero)
        #expect(await cache.thumbnail(for: url, size: size, scale: 2) != nil)
        #expect(await probe.starts == 2)
    }

    @Test func anEditedFileRendersAgain() async {
        await probe.setDelay(.zero)
        let cache = cache()
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await cache.thumbnail(for: url, size: size, scale: 2, modified: saved)
        _ = await cache.thumbnail(for: url, size: size, scale: 2, modified: saved)
        #expect(await probe.starts == 1)
        _ = await cache.thumbnail(for: url, size: size, scale: 2, modified: saved.addingTimeInterval(60))
        #expect(await probe.starts == 2)
    }
}

/// Counts renders and their cancellations, and sets how long the next render takes.
private actor ThumbnailRenderProbe {
    private(set) var starts = 0
    private(set) var cancellations = 0
    private var delay: Duration = .zero

    func setDelay(_ delay: Duration) { self.delay = delay }

    /// Records a render and returns how long it takes.
    func started() -> Duration {
        starts += 1
        return delay
    }

    func wasCancelled() { cancellations += 1 }
}

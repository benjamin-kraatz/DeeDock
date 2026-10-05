import Foundation
import Testing
@testable import DeeDock

struct FolderStackMediaCacheTests {
    @Test("The oldest media header is evicted once the cache reaches capacity")
    func evictsOldestAtCapacity() async {
        let cache = FolderStackMediaCache()
        let capacity = FolderStackMediaCache.capacity
        let keys = (0..<capacity).map(mediaKey)
        for key in keys {
            await cache.store(.unavailable, for: key)
        }
        #expect(await cache.value(for: keys[0]) == .unavailable)
        #expect(await cache.insertionCount == capacity)

        let extra = mediaKey(capacity)
        await cache.store(.metadata(.pdf(pageCount: 3)), for: extra)

        #expect(await cache.value(for: keys[0]) == nil)
        #expect(await cache.value(for: keys[1]) == .unavailable)
        #expect(await cache.value(for: keys[capacity - 1]) == .unavailable)
        #expect(await cache.value(for: extra) == .metadata(.pdf(pageCount: 3)))
        #expect(await cache.insertionCount == capacity)
    }

    @Test("Re-storing an existing key does not append another order entry")
    func restoreDoesNotDuplicateOrder() async {
        let cache = FolderStackMediaCache()
        let capacity = FolderStackMediaCache.capacity
        let keys = (0..<capacity).map(mediaKey)
        for key in keys {
            await cache.store(.unavailable, for: key)
        }

        let updated = FolderStackMediaCacheValue.metadata(.image(width: 4, height: 5))
        for _ in 0..<capacity {
            await cache.store(updated, for: keys[0])
        }

        #expect(await cache.insertionCount == capacity)
        #expect(await cache.value(for: keys[0]) == updated)
        #expect(await cache.value(for: keys[1]) == .unavailable)

        let extra = mediaKey(capacity)
        await cache.store(.unavailable, for: extra)

        #expect(await cache.insertionCount == capacity)
        #expect(await cache.value(for: keys[0]) == nil)
        #expect(await cache.value(for: keys[1]) == .unavailable)
        #expect(await cache.value(for: extra) == .unavailable)
    }

    @Test("Retained keys still return the value that was stored")
    func retainedKeysStillHit() async {
        let cache = FolderStackMediaCache()
        let capacity = FolderStackMediaCache.capacity
        let keys = (0..<capacity).map(mediaKey)
        for (index, key) in keys.enumerated() {
            await cache.store(.metadata(.image(width: index + 1, height: 8)), for: key)
        }

        let extra = mediaKey(capacity)
        await cache.store(.metadata(.audio(duration: 1.5)), for: extra)

        #expect(await cache.value(for: keys[0]) == nil)
        for index in 1..<capacity {
            #expect(await cache.value(for: keys[index]) == .metadata(.image(width: index + 1, height: 8)))
        }
        #expect(await cache.value(for: extra) == .metadata(.audio(duration: 1.5)))
    }

    private func mediaKey(_ index: Int) -> FolderStackMediaCacheKey {
        FolderStackMediaCacheKey(
            FolderStackEntryReference(
                url: URL(fileURLWithPath: "/Preview/media-\(index).png"),
                name: "media-\(index).png",
                isFolder: false,
                byteCount: Int64(index),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        )
    }
}

// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Darwin

/// The vectors search scores, as stored (float16), plus room to turn `blockRows` of them into float32 at a time.
/// Half the memory of keeping float32 (70,000 vectors: 108 MB instead of 215) for ~2 ms more a query (2026-10-09).
///
/// It's mmap'd so that releasing it really frees it. Malloc keeps freed large blocks in its cache: a freed 60 MB matrix
/// (20k vectors) stayed in the app's footprint even after `malloc_zone_pressure_relief` (measured 2026-10-07), while
/// `munmap` returns it at once. Fresh anonymous pages are zeroed.
nonisolated final class VectorStorage {
    static let blockRows = 1024
    let rows: Int
    /// `rows` × `Vectors.dimension`.
    let halves: UnsafeMutablePointer<Float16>
    /// `blockRows` × `Vectors.dimension`.
    let block: UnsafeMutablePointer<Float>
    private let raw: UnsafeMutableRawPointer
    private let bytes: Int

    /// Nil for no rows, or when the memory can't be mapped.
    init?(rows: Int) {
        guard rows > 0 else { return nil }
        let halfBytes = rows * Vectors.dimension * MemoryLayout<Float16>.stride
        let blockBytes = Self.blockRows * Vectors.dimension * MemoryLayout<Float>.stride
        bytes = halfBytes + blockBytes
        guard let raw = mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0), raw != MAP_FAILED
        else { return nil }
        self.raw = raw
        self.rows = rows
        halves = raw.bindMemory(to: Float16.self, capacity: rows * Vectors.dimension)
        block = (raw + halfBytes).bindMemory(to: Float.self, capacity: Self.blockRows * Vectors.dimension)
    }

    deinit {
        munmap(raw, bytes)
    }
}

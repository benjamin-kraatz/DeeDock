import Foundation
import Testing
@testable import DeeDock

/// Vectors stored as float16 come back as the same float16 values, widened to float32 for scoring.
struct LookoutVectorStorageTests {
    @Test func halfVectorsConvertBackExactly() throws {
        let vector = (0..<Vectors.dimension).map { Float(sin(Double($0) * 0.37)) * 0.05 }
        let blob = Vectors.half(vector)
        #expect(blob.count == Vectors.dimension * 2)   // 1.5 KB a vector
        let storage = try #require(VectorStorage(rows: 2))
        blob.copyBytes(to: UnsafeMutableRawBufferPointer(start: storage.halves + Vectors.dimension,
                                                         count: Vectors.dimension * 2))
        Vectors.floats(fromHalf: storage.halves, count: Vectors.dimension * 2, to: storage.block)
        let back = Array(UnsafeBufferPointer(start: storage.block + Vectors.dimension, count: Vectors.dimension))
        #expect(back == vector.map { Float(Float16($0)) })
        #expect(storage.block[0] == 0)   // fresh mmap'd memory is zeroed, and row 0 was left alone
    }

    @Test func aStoredBlobReadsBackAsTheSameVector() throws {
        let folder = LookoutTestFolder()
        let store = try IndexStore(directory: folder.url)
        let id = try store.insert(Candidate(path: "/a/x.png", kind: .image, size: 1, mtime: 1, inode: 1, device: 1))
        let vector = (0..<Vectors.dimension).map { Float($0 % 11) / 11 - 0.5 }
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        var blob: Data?
        try store.db.query("SELECT vec FROM segments WHERE vec IS NOT NULL") { blob = $0.blob(0) }
        let stored = try #require(blob)
        let halves = stored.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        #expect(halves.map(Float.init) == vector.map { Float(Float16($0)) })
    }

    @Test func noRowsNeedNoStorage() {
        #expect(VectorStorage(rows: 0) == nil)
    }
}

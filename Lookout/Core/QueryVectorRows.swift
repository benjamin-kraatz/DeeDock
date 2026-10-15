import Foundation

/// The wire format of vectors crossing the query service's XPC connection: rows of `dimension` Float32 values, packed
/// one after another in little-endian byte order with no header. A row count is implied by the byte count.
///
/// The service encodes; the app decodes. Plain `Data` keeps the XPC interface free of custom secure-coding classes and
/// costs 3 KB per query.
nonisolated enum QueryVectorRows {
    /// EmbeddingGemma 2's output width.
    static let dimension = 768

    /// Packs `rows` in order. Every row must have `dimension` values.
    static func encode(_ rows: [[Float]]) -> Data {
        var data = Data(capacity: rows.count * dimension * MemoryLayout<UInt32>.size)
        for row in rows {
            precondition(row.count == dimension, "a vector has \(row.count) values, not \(dimension)")
            for value in row {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    /// Unpacks the rows, or nil when the byte count isn't a whole number of rows.
    static func decode(_ data: Data) -> [[Float]]? {
        let rowBytes = dimension * MemoryLayout<UInt32>.size
        guard data.count % rowBytes == 0 else { return nil }
        return data.withUnsafeBytes { buffer in
            (0..<(data.count / rowBytes)).map { row in
                (0..<dimension).map { column in
                    let offset = row * rowBytes + column * MemoryLayout<UInt32>.size
                    let bits = buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                    return Float(bitPattern: UInt32(littleEndian: bits))
                }
            }
        }
    }
}

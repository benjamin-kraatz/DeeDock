import CoreGraphics
import Foundation

/// A playful provenance mesh for the public marketing version and build.
///
/// The running app draws this as a tiled bitmap behind settings chrome, the Appearance preview,
/// and Window Peek surfaces. Ink cells shift luminance by about 1.5 percent, which disappears into
/// a fill or a material and leaves control contrast alone. It is not a fingerprint, a license, or
/// a copy-protection scheme: the only payload is the version string already shown in About.
///
/// Payload shape is `marketing+build`, for example `0.9.2+33`, using `CFBundleShortVersionString`
/// and `CFBundleVersion`. The alphabet is `0-9.+`.
///
/// To read a screenshot by eye, capture the Settings window as a PNG. Text already spans the full
/// range, so crop a quiet patch of card fill or a gap between cards before opening Tools → Adjust
/// Color. Push Contrast up, or pull the histogram endpoints in, until a repeating line of the
/// version appears. Light appearance darkens the ink; dark appearance lightens it. `read(_:)`
/// recovers the same string from the whole image; it compares each cell with its neighbors and
/// does not need the crop.
enum StudioMark {
    /// One cell edge in the tile image, in pixels. Drawn at 1×, so each cell is also this many points.
    /// A Retina window screenshot then stores twice that many pixels per cell.
    static let pixelsPerCell = 2

    /// Fraction of white added in dark appearance, or of black mixed in light appearance.
    /// About four 8-bit levels on a mid gray fill.
    static let amplitude = 0.015

    /// `CFBundleShortVersionString+CFBundleVersion` from the built app, restricted to the mesh alphabet.
    static var payload: String {
        let info = AppVersionInfo.current
        return format(version: info.version, build: info.build)
    }

    /// Joins a marketing version and build, dropping any character the mesh cannot draw.
    static func format(version: String, build: String?) -> String {
        let combined: String
        if let build, !build.isEmpty {
            combined = "\(version)+\(build)"
        } else {
            combined = version
        }
        return String(combined.filter { glyphs[$0] != nil })
    }

    /// Cell size of one tile, including the quiet border and the sync bars.
    static func gridSize(payload: String) -> (width: Int, height: Int)? {
        guard let mask = Self.mask(for: payload) else { return nil }
        return (mask.width, mask.height)
    }

    /// Tile image for `payload`. `inkWhite` is the dark-appearance glyph; light appearance uses black ink.
    static func tileImage(payload: String, inkWhite: Bool) -> CGImage? {
        guard let mask = Self.mask(for: payload) else { return nil }
        let width = mask.width * pixelsPerCell
        let height = mask.height * pixelsPerCell
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        let channel: UInt8 = inkWhite ? 255 : 0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.ink[y * mask.width + x] {
                for dy in 0..<pixelsPerCell {
                    for dx in 0..<pixelsPerCell {
                        let pixel = ((y * pixelsPerCell + dy) * width + (x * pixelsPerCell + dx)) * 4
                        data[pixel] = channel
                        data[pixel + 1] = channel
                        data[pixel + 2] = channel
                        data[pixel + 3] = 255
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Recovers a payload from an 8-bit screenshot. Tries both row orders because bitmap contexts and
    /// window captures do not agree on which edge is the top.
    static func read(_ image: CGImage) -> String? {
        guard let samples = luminance(of: image) else { return nil }
        let width = image.width
        let height = image.height
        if let text = read(samples: samples, width: width, height: height) { return text }
        return read(samples: flipVertical(samples, width: width, height: height), width: width, height: height)
    }

    /// Recovers a payload from top-left grayscale samples. `nil` when no tile clears the sync bars.
    static func read(samples: [UInt8], width: Int, height: Int) -> String? {
        guard width > 0, height > 0, samples.count == width * height else { return nil }
        var best: (separation: Int, text: String)?
        // Retina captures of the 2-point cells land on 4 pixels; 2 covers a 1× capture of the same tile.
        for scale in [4, 2, 3, 1] {
            for phaseY in 0..<scale {
                for phaseX in 0..<scale {
                    guard let means = cellMeans(samples, width: width, height: height, scale: scale, phaseX: phaseX, phaseY: phaseY) else {
                        continue
                    }
                    if let found = find(in: means.samples, columns: means.columns, rows: means.rows),
                       best == nil || found.separation > best!.separation {
                        best = found
                        // A clean tile is several levels away from the fill; stop before finer scales.
                        if found.separation >= 4 { return found.text }
                    }
                }
            }
        }
        return best?.text
    }

    /// Flat field with the mesh stamped on, for tests. `lift` is added to ink samples (negative darkens).
    static func renderedSamples(payload: String, background: Int, lift: Int, scale: Int, phaseX: Int, phaseY: Int,
                                repeatsX: Int, repeatsY: Int, gradient: Bool = false) -> (samples: [UInt8], width: Int, height: Int)? {
        guard scale > 0, let mask = Self.mask(for: payload) else { return nil }
        let width = phaseX + repeatsX * mask.width * scale + 5
        let height = phaseY + repeatsY * mask.height * scale + 7
        var samples = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let base = background + (gradient ? x / 30 : 0)
                samples[y * width + x] = UInt8(clamping: base)
            }
        }
        for repeatY in 0..<repeatsY {
            for repeatX in 0..<repeatsX {
                let originX = phaseX + repeatX * mask.width * scale
                let originY = phaseY + repeatY * mask.height * scale
                for y in 0..<mask.height {
                    for x in 0..<mask.width where mask.ink[y * mask.width + x] {
                        for dy in 0..<scale {
                            for dx in 0..<scale {
                                let index = (originY + y * scale + dy) * width + (originX + x * scale + dx)
                                samples[index] = UInt8(clamping: Int(samples[index]) + lift)
                            }
                        }
                    }
                }
            }
        }
        return (samples, width, height)
    }

    // MARK: - Glyphs

    /// 5×7 glyphs, top row first. The low five bits are the row; bit 4 is the leftmost pixel.
    /// Digits differ by at least three bits, so one flipped cell still names the right character.
    private static let glyphWidth = 5
    private static let glyphHeight = 7
    private static let quiet = 1
    private static let glyphs: [Character: [UInt8]] = [
        "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        "3": [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110],
        "4": [0b00100, 0b01100, 0b10100, 0b10100, 0b11111, 0b00100, 0b00100],
        "5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
        "6": [0b01110, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b01110],
        "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110],
        ".": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100],
        "+": [0b00100, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00100],
    ]

    private struct Mask {
        let width: Int
        let height: Int
        let ink: [Bool]
    }

    /// Quiet border, two full bars with a gap between them, then the payload.
    /// The bars are the sync the reader searches for; no glyph contains that pair.
    private static func mask(for payload: String) -> Mask? {
        guard !payload.isEmpty, payload.allSatisfy({ glyphs[$0] != nil }) else { return nil }
        let width = quiet + 3 + 1 + payload.count * (glyphWidth + 1) + quiet
        let height = quiet + glyphHeight + quiet
        var ink = [Bool](repeating: false, count: width * height)
        for y in 0..<glyphHeight {
            ink[(quiet + y) * width + quiet] = true
            ink[(quiet + y) * width + quiet + 2] = true
        }
        var cursor = quiet + 3 + 1
        for character in payload {
            guard let glyph = glyphs[character] else { return nil }
            for y in 0..<glyphHeight {
                let bits = glyph[y]
                for bit in 0..<glyphWidth where bits & UInt8(1 << (glyphWidth - 1 - bit)) != 0 {
                    ink[(quiet + y) * width + cursor + bit] = true
                }
            }
            cursor += glyphWidth + 1
        }
        return Mask(width: width, height: height, ink: ink)
    }

    private static func isPayload(_ text: String) -> Bool {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, isDottedNumber(parts[0]) else { return false }
        guard parts.count == 2 else { return true }
        return !parts[1].isEmpty && parts[1].allSatisfy(\.isNumber)
    }

    private static func isDottedNumber(_ text: Substring) -> Bool {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count >= 2 else { return false }
        return pieces.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func luminance(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        var samples = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let pixel = index * 4
            samples[index] = UInt8((Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2])) / 3)
        }
        return samples
    }

    private static func flipVertical(_ samples: [UInt8], width: Int, height: Int) -> [UInt8] {
        var flipped = [UInt8](repeating: 0, count: samples.count)
        for y in 0..<height {
            let source = (height - 1 - y) * width
            let destination = y * width
            for x in 0..<width {
                flipped[destination + x] = samples[source + x]
            }
        }
        return flipped
    }

    private static func cellMeans(_ samples: [UInt8], width: Int, height: Int, scale: Int, phaseX: Int, phaseY: Int) -> (samples: [Int], columns: Int, rows: Int)? {
        let columns = (width - phaseX) / scale
        let rows = (height - phaseY) / scale
        let tileHeight = quiet + glyphHeight + quiet
        let minimumWidth = quiet + 3 + 1 + (glyphWidth + 1) + quiet
        guard columns >= minimumWidth, rows >= tileHeight else { return nil }
        var means = [Int](repeating: 0, count: columns * rows)
        let area = scale * scale
        for row in 0..<rows {
            for column in 0..<columns {
                let x0 = phaseX + column * scale
                let y0 = phaseY + row * scale
                var sum = 0
                for dy in 0..<scale {
                    let start = (y0 + dy) * width + x0
                    for dx in 0..<scale {
                        sum += Int(samples[start + dx])
                    }
                }
                means[row * columns + column] = sum / area
            }
        }
        return (means, columns, rows)
    }

    private static func find(in means: [Int], columns: Int, rows: Int) -> (separation: Int, text: String)? {
        let tileHeight = quiet + glyphHeight + quiet
        let minimumWidth = quiet + 3 + 1 + (glyphWidth + 1) + quiet
        guard columns >= minimumWidth, rows >= tileHeight else { return nil }
        var best: (separation: Int, text: String)?
        for y in 0...(rows - tileHeight) {
            for x in 0...(columns - minimumWidth) {
                guard let found = readTile(means, columns: columns, originX: x, originY: y) else { continue }
                if best == nil || found.separation > best!.separation {
                    best = found
                }
            }
        }
        return best
    }

    private static func readTile(_ means: [Int], columns: Int, originX: Int, originY: Int) -> (separation: Int, text: String)? {
        func at(_ x: Int, _ y: Int) -> Int {
            means[(originY + y) * columns + (originX + x)]
        }

        let paperSamples = (0..<glyphHeight).map { at(quiet + 1, quiet + $0) }
        var inkSamples: [Int] = []
        inkSamples.reserveCapacity(glyphHeight * 2)
        for y in 0..<glyphHeight {
            inkSamples.append(at(quiet, quiet + y))
            inkSamples.append(at(quiet + 2, quiet + y))
        }
        let paper = paperSamples.reduce(0, +) / paperSamples.count
        let ink = inkSamples.reduce(0, +) / inkSamples.count
        let delta = ink - paper
        guard abs(delta) >= 2 else { return nil }
        let half = paper + delta / 2
        func isInk(_ value: Int, half: Int) -> Bool {
            delta > 0 ? value >= half : value <= half
        }
        guard inkSamples.allSatisfy({ isInk($0, half: half) }),
              paperSamples.allSatisfy({ !isInk($0, half: half) }) else { return nil }
        for column in [quiet, quiet + 1, quiet + 2] {
            if isInk(at(column, 0), half: half) || isInk(at(column, quiet + glyphHeight), half: half) {
                return nil
            }
        }
        for y in 0..<glyphHeight where isInk(at(0, quiet + y), half: half) {
            return nil
        }

        var text = ""
        var cursor = quiet + 3 + 1
        while cursor + glyphWidth <= columns - originX, text.count < 32 {
            let gap = (0..<glyphHeight).map { at(cursor - 1, quiet + $0) }
            let localPaper = gap.reduce(0, +) / gap.count
            let localHalf = localPaper + delta / 2
            if gap.filter({ isInk($0, half: localHalf) }).count > 1 { break }
            var rows: [UInt8] = []
            var inkCount = 0
            for y in 0..<glyphHeight {
                var bits: UInt8 = 0
                for bit in 0..<glyphWidth where isInk(at(cursor + bit, quiet + y), half: localHalf) {
                    bits |= UInt8(1 << (glyphWidth - 1 - bit))
                    inkCount += 1
                }
                rows.append(bits)
            }
            if inkCount == 0 { break }
            var bestCharacter: Character?
            var bestDistance = Int.max
            for (character, glyph) in glyphs {
                let distance = hamming(rows, glyph)
                if distance < bestDistance {
                    bestDistance = distance
                    bestCharacter = character
                }
            }
            guard let bestCharacter, bestDistance <= 1 else { break }
            text.append(bestCharacter)
            cursor += glyphWidth + 1
        }
        guard isPayload(text) else { return nil }
        return (abs(delta), text)
    }

    private static func hamming(_ rows: [UInt8], _ glyph: [UInt8]) -> Int {
        var distance = 0
        for index in 0..<glyphHeight {
            var bits = (rows[index] ^ glyph[index]) & 0b1_1111
            while bits != 0 {
                distance += Int(bits & 1)
                bits >>= 1
            }
        }
        return distance
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct StudioMarkTests {
    @Test("The public payload is the marketing version plus the build")
    func payloadFormat() {
        #expect(StudioMark.format(version: "0.9.2", build: "33") == "0.9.2+33")
        #expect(StudioMark.format(version: "1.0", build: nil) == "1.0")
        #expect(StudioMark.format(version: "1.0", build: "") == "1.0")
        #expect(StudioMark.format(version: "0.9.2-beta", build: "33") == "0.9.2+33")
        #expect(StudioMark.format(version: "beta", build: nil).isEmpty)
    }

    @Test("A flat field round-trips the version when the ink is lighter or darker")
    func roundTripPolarity() throws {
        for (background, lift) in [(248, -4), (36, 4)] {
            let rendered = try #require(StudioMark.renderedSamples(
                payload: "0.9.2+33", background: background, lift: lift, scale: 1,
                phaseX: 0, phaseY: 0, repeatsX: 2, repeatsY: 2))
            #expect(StudioMark.read(samples: rendered.samples, width: rendered.width, height: rendered.height) == "0.9.2+33")
        }
    }

    @Test("Retina scale, a phase offset, and a slow gradient still read the full build")
    func scaledGradient() throws {
        let rendered = try #require(StudioMark.renderedSamples(
            payload: "0.9.2+33", background: 200, lift: -5, scale: 2,
            phaseX: 1, phaseY: 2, repeatsX: 1, repeatsY: 2, gradient: true))
        #expect(StudioMark.read(samples: rendered.samples, width: rendered.width, height: rendered.height) == "0.9.2+33")

        let retina = try #require(StudioMark.renderedSamples(
            payload: "0.9.2+33", background: 32, lift: 4, scale: 4,
            phaseX: 3, phaseY: 5, repeatsX: 2, repeatsY: 2))
        #expect(StudioMark.read(samples: retina.samples, width: retina.width, height: retina.height) == "0.9.2+33")
    }

    @Test("Covering one tile and a little sample noise still leaves a readable tile")
    func coveredTile() throws {
        let payload = "0.9.2+33"
        let scale = 2
        let phaseX = 4
        let phaseY = 6
        var rendered = try #require(StudioMark.renderedSamples(
            payload: payload, background: 230, lift: -4, scale: scale,
            phaseX: phaseX, phaseY: phaseY, repeatsX: 2, repeatsY: 2))
        let grid = try #require(StudioMark.gridSize(payload: payload))
        for index in rendered.samples.indices {
            let x = index % rendered.width
            let y = index / rendered.width
            if x < phaseX + grid.width * scale && y < phaseY + grid.height * scale {
                rendered.samples[index] = 20
            } else if (x * 3 + y) % 7 == 0 {
                let nudge = (x + y) % 2 == 0 ? 1 : -1
                rendered.samples[index] = UInt8(clamping: Int(rendered.samples[index]) + nudge)
            }
        }
        #expect(StudioMark.read(samples: rendered.samples, width: rendered.width, height: rendered.height) == payload)
    }

    @Test("A flat image without the mesh reads as nothing")
    func blank() {
        let samples = [UInt8](repeating: 128, count: 80 * 40)
        #expect(StudioMark.read(samples: samples, width: 80, height: 40) == nil)
    }

    @Test("Reading a CGImage survives whichever row the bitmap treats as the top")
    func cgImageRoundTrip() throws {
        let rendered = try #require(StudioMark.renderedSamples(
            payload: "1.0.0+2", background: 250, lift: -3, scale: 1,
            phaseX: 2, phaseY: 1, repeatsX: 1, repeatsY: 2))
        let image = try #require(grayImage(rendered.samples, width: rendered.width, height: rendered.height))
        #expect(StudioMark.read(image) == "1.0.0+2")
    }

    private func grayImage(_ samples: [UInt8], width: Int, height: Int) -> CGImage? {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for index in samples.indices {
            let pixel = index * 4
            data[pixel] = samples[index]
            data[pixel + 1] = samples[index]
            data[pixel + 2] = samples[index]
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

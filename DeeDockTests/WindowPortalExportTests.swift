import CoreGraphics
import Foundation
import Testing

struct WindowPortalExportTests {
    private func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test("A saved frame covers the viewport in image pixels, measured from the top-left")
    func viewportCrop() {
        let source = image(width: 400, height: 200)
        let cropped = WindowPortalExport.visibleFrame(
            of: source, viewport: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5))
        #expect(cropped?.width == 200)
        #expect(cropped?.height == 100)
    }

    @Test("A whole-window viewport keeps the frame itself and a degenerate one saves nothing")
    func viewportBounds() {
        let source = image(width: 120, height: 80)
        let whole = WindowPortalExport.visibleFrame(
            of: source, viewport: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(whole?.width == 120 && whole?.height == 80)
        #expect(WindowPortalExport.visibleFrame(
            of: source, viewport: CGRect(x: 2, y: 2, width: 0.5, height: 0.5)) == nil)
    }

    @Test("PNG data is produced for a captured frame")
    func encoding() throws {
        let data = try #require(WindowPortalExport.png(image(width: 32, height: 16)))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("File names keep the window's identity without path separators or colons")
    func filenames() {
        let date = Date(timeIntervalSince1970: 1_757_354_979)
        let name = WindowPortalExport.suggestedFilename(source: "Xcode: DeeDock/main", at: date)
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(name.hasPrefix("Xcode DeeDock main "))
        #expect(name.hasSuffix(".png"))
        #expect(WindowPortalExport.suggestedFilename(source: "  ", at: date).hasPrefix("Portal "))
    }
}

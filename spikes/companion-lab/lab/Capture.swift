import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// What the user handed to the companion.
enum CompanionContext {
    case text(String)
    case region(CGImage, recognized: String)
    case window(CGImage?, text: String, source: String)

    var label: String {
        switch self {
        case .text(let text): return "“\(text.prefix(18).trimmingCharacters(in: .whitespacesAndNewlines))…”"
        case .region(_, let recognized): return "Region · \(recognized.split(whereSeparator: \.isWhitespace).count) words"
        case .window(_, _, let source): return "Whole window · \(source)"
        }
    }
    var symbol: String {
        switch self { case .text: "text.quote"; case .region: "viewfinder"; case .window: "macwindow" }
    }
    var text: String {
        switch self { case .text(let t): t; case .region(_, let r): r; case .window(_, let t, _): t }
    }
    var image: CGImage? {
        switch self { case .text: nil; case .region(let i, _): i; case .window(let i, _, _): i }
    }
}

struct AXSelection {
    let text: String
    let element: AXUIElement
    let replaceable: Bool
}

enum ContextReader {
    /// Reads the user's current selection in another app without touching the clipboard.
    static func selection(pid: pid_t) -> AXSelection? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let focused = AX.element(app, kAXFocusedUIElementAttribute) else { return nil }
        if let text = AX.copy(focused, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AXSelection(text: text, element: focused, replaceable: AX.settable(focused, kAXSelectedTextAttribute))
        }
        // WebKit and Chromium web content report selection through text markers.
        if let range = AX.copy(focused, "AXSelectedTextMarkerRange") {
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, range, &out) == .success,
               let text = out as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AXSelection(text: text, element: focused, replaceable: false)
            }
        }
        return nil
    }

    /// Bounded walk that collects visible text from a window's accessibility tree.
    static func windowText(_ window: AXUIElement, budget: TimeInterval = 0.35, limit: Int = 8_000) -> String {
        let deadline = Date().addingTimeInterval(budget)
        var pieces: [String] = []
        var total = 0
        var queue: [AXUIElement] = [window]
        while !queue.isEmpty, Date() < deadline, total < limit {
            let element = queue.removeFirst()
            let role = AX.copy(element, kAXRoleAttribute) as? String ?? ""
            if ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading"].contains(role) {
                for key in [kAXValueAttribute, kAXTitleAttribute] {
                    if let s = AX.copy(element, key) as? String, !s.isEmpty { pieces.append(s); total += s.count; break }
                }
                if role == "AXTextArea" { continue }   // terminal/text views: value already holds the content
            }
            queue.append(contentsOf: AX.children(element))
        }
        return String(pieces.joined(separator: "\n").prefix(limit))
    }

    /// Chromium only builds its web accessibility tree for assistive clients. Electron honours
    /// AXManualAccessibility; Chromium browsers need AXEnhancedUserInterface (returns -25208 but works).
    static func wakeWebAccessibility(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success { return false }
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return true
    }

    static func restoreEnhancedUserInterface(pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    }
}

/// One-shot captures of the target window only. Our own panels are never in the picture.
actor WindowCapture {
    func image(windowID: CGWindowID, rect: CGRect? = nil, maxPixels: CGFloat = 2_048) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let source = rect ?? CGRect(origin: .zero, size: window.frame.size)
        let scale = min(2, maxPixels / max(source.width, source.height))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = max(1, Int(source.width * scale))
        configuration.height = max(1, Int(source.height * scale))
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                           configuration: configuration)
    }

    /// Median colour of the strip just under the tab's footprint, a few points below the window's top rim.
    func titlebarColor(windowID: CGWindowID, xRange: ClosedRange<CGFloat>, fromBottom: Bool = false) async -> NSColor? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let width = max(8, xRange.upperBound - xRange.lowerBound)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: max(0, xRange.lowerBound), y: 2, width: width, height: 5)
        configuration.width = Int(width * 2)
        configuration.height = 10
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                     configuration: configuration) else { return nil }
        return Self.median(image)
    }

    private static func median(_ image: CGImage) -> NSColor? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r: [UInt8] = [], g: [UInt8] = [], b: [UInt8] = []
        for i in stride(from: 0, to: data.count, by: 4) { r.append(data[i]); g.append(data[i + 1]); b.append(data[i + 2]) }
        func m(_ v: [UInt8]) -> CGFloat { CGFloat(v.sorted()[v.count / 2]) / 255 }
        return NSColor(srgbRed: m(r), green: m(g), blue: m(b), alpha: 1)
    }

    /// The first recognition in a process loads Vision's models (~13 s measured on macOS 27);
    /// later calls take ~50–65 ms. Run once in the background when the companion is enabled.
    func prewarm() async {
        let size = CGSize(width: 220, height: 40)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Companion" as NSString).draw(at: NSPoint(x: 8, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 22)])
            return true
        }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let started = Date()
        _ = await recognizeText(cg)
        lab("OCR prewarmed in \(Int(Date().timeIntervalSince(started) * 1000))ms")
    }

    func recognizeText(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return "" }
        return observations.map(\.transcript).joined(separator: "\n")
    }
}

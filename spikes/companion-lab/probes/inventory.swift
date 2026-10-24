import AppKit
import ApplicationServices
import ScreenCaptureKit

// Private but long-stable (used by AltTab, Rectangle, Hammerspoon): AX window -> CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func settable(_ e: AXUIElement, _ a: String) -> Bool {
    var s: DarwinBoolean = false; return AXUIElementIsAttributeSettable(e, a as CFString, &s) == .success && s.boolValue
}
func frame(_ w: AXUIElement) -> CGRect? {
    guard let p = attr(w, kAXPositionAttribute), let s = attr(w, kAXSizeAttribute) else { return nil }
    var o = CGPoint.zero, z = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &o); AXValueGetValue(s as! AXValue, .cgSize, &z)
    return CGRect(origin: o, size: z)
}
func ms(_ t: UInt64) -> String { String(format: "%.1fms", Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6) }

struct TreeStats { var count = 0; var chars = 0; var roles: [String: Int] = [:]; var truncated = false }
func walk(_ e: AXUIElement, depth: Int, _ s: inout TreeStats, deadline: UInt64) {
    if s.count >= 4000 || depth > 60 || DispatchTime.now().uptimeNanoseconds > deadline { s.truncated = true; return }
    s.count += 1
    let role = (attr(e, kAXRoleAttribute) as? String) ?? "?"
    s.roles[role, default: 0] += 1
    for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let str = attr(e, key) as? String { s.chars += str.count }
    }
    guard let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return }
    for k in kids { walk(k, depth: depth + 1, &s, deadline: deadline) }
}

func median(_ v: [UInt8]) -> UInt8 { let s = v.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }

@main struct Inventory {
    static func main() async throws {
        _ = NSApplication.shared
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps {
            let pid = app.processIdentifier
            let name = app.localizedName ?? "?"
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.5)
            var t = DispatchTime.now().uptimeNanoseconds
            let focusedWin = attr(axApp, kAXFocusedWindowAttribute) ?? (attr(axApp, kAXWindowsAttribute) as? [AXUIElement])?.first
            guard let fw = focusedWin, CFGetTypeID(fw) == AXUIElementGetTypeID() else { print("## \(name): no AX window"); continue }
            let w = fw as! AXUIElement
            let tFocus = ms(t)
            var wid: CGWindowID = 0
            let idErr = _AXUIElementGetWindow(w, &wid)
            let role = attr(w, kAXRoleAttribute) as? String ?? "?"
            let sub = attr(w, kAXSubroleAttribute) as? String ?? "?"
            let fr = frame(w) ?? .zero
            print("## \(name) [\(app.bundleIdentifier ?? "-")] focusedWindow \(tFocus) role=\(role)/\(sub) frame=\(fr.integral) _AXUIElementGetWindow=\(idErr == .success ? String(wid) : "err \(idErr.rawValue)")")

            // Title-bar color: capture the window's top 24 pt strip and sample the top rows.
            if let scw = content.windows.first(where: { $0.windowID == wid }) {
                t = DispatchTime.now().uptimeNanoseconds
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = CGRect(x: 0, y: 0, width: scw.frame.width, height: 24)
                cfg.width = Int(scw.frame.width * 2); cfg.height = 48
                cfg.captureResolution = .best; cfg.showsCursor = false; cfg.ignoreShadowsSingleWindow = true
                do {
                    let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scw), configuration: cfg)
                    let tCap = ms(t)
                    let rep = NSBitmapImageRep(cgImage: img)
                    func sample(_ x0: Double, _ x1: Double, rows: ClosedRange<Int>) -> (UInt8, UInt8, UInt8) {
                        var r: [UInt8] = [], g: [UInt8] = [], b: [UInt8] = []
                        for y in rows { for x in stride(from: Int(Double(rep.pixelsWide) * x0), to: Int(Double(rep.pixelsWide) * x1), by: 2) {
                            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                            r.append(UInt8(c.redComponent * 255)); g.append(UInt8(c.greenComponent * 255)); b.append(UInt8(c.blueComponent * 255))
                        } }
                        return (median(r), median(g), median(b))
                    }
                    let hex = { (c: (UInt8, UInt8, UInt8)) in String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
                    print("   titlebar top rows: left \(hex(sample(0.15, 0.30, rows: 6...10)))  center \(hex(sample(0.42, 0.58, rows: 6...10)))  right \(hex(sample(0.70, 0.85, rows: 6...10)))  capture \(tCap) img \(img.width)x\(img.height)")
                    let safe = name.replacingOccurrences(of: " ", with: "_")
                    if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: "out/strip-\(safe).png")) }
                } catch { print("   capture failed: \(error.localizedDescription)") }
            } else { print("   no SCWindow match for id \(wid)") }

            // Focused element + selected text.
            if let fe = attr(axApp, kAXFocusedUIElementAttribute), CFGetTypeID(fe) == AXUIElementGetTypeID() {
                let el = fe as! AXUIElement
                let r = attr(el, kAXRoleAttribute) as? String ?? "?"
                let sel = attr(el, kAXSelectedTextAttribute) as? String
                let hasRange = attr(el, kAXSelectedTextRangeAttribute) != nil
                let hasMarker = attr(el, "AXSelectedTextMarkerRange") != nil
                print("   focusedElement role=\(r) selectedText=\(sel.map { "\"\($0.prefix(40))\" (\($0.count))" } ?? "nil") range=\(hasRange) textMarkerRange=\(hasMarker) settable[AXSelectedText]=\(settable(el, kAXSelectedTextAttribute)) settable[AXValue]=\(settable(el, kAXValueAttribute))")
            } else { print("   focusedElement: none") }

            // Tree richness under the window.
            t = DispatchTime.now().uptimeNanoseconds
            var s = TreeStats()
            walk(w, depth: 0, &s, deadline: t + 1_500_000_000)
            let top = s.roles.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            print("   AX tree: \(s.count) elements\(s.truncated ? "+ (truncated)" : ""), \(s.chars) text chars, \(ms(t)); \(top)")
        }
    }
}

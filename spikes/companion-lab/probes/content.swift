import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func names(_ e: AXUIElement) -> [String] { var n: CFArray?; AXUIElementCopyAttributeNames(e, &n); return (n as? [String]) ?? [] }
func pnames(_ e: AXUIElement) -> [String] { var n: CFArray?; AXUIElementCopyParameterizedAttributeNames(e, &n); return (n as? [String]) ?? [] }
func ms(_ t: UInt64) -> String { String(format: "%.0fms", Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6) }
func count(_ e: AXUIElement, _ n: inout Int, _ chars: inout Int, deadline: UInt64) {
    if n > 6000 || DispatchTime.now().uptimeNanoseconds > deadline { return }
    n += 1
    for k in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] { if let s = attr(e, k) as? String { chars += s.count } }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { count(c, &n, &chars, deadline: deadline) }
}
func find(_ e: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
    if (attr(e, kAXRoleAttribute) as? String) == role { return e }
    if depth > 12 { return nil }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, role: role, depth: depth + 1) { return f } }
    return nil
}
func pid(_ bundle: String) -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier }

// 1. Ghostty: what does the terminal surface expose?
if let p = pid("com.mitchellh.ghostty") {
    let app = AXUIElementCreateApplication(p)
    if let w = attr(app, kAXFocusedWindowAttribute), let area = find(w as! AXUIElement, role: "AXTextArea") {
        let v = attr(area, kAXValueAttribute) as? String ?? ""
        let lines = v.split(separator: "\n", omittingEmptySubsequences: false)
        print("Ghostty AXTextArea: value \(v.count) chars, \(lines.count) lines")
        print("  attributes: \(names(area).joined(separator: ", "))")
        print("  parameterized: \(pnames(area).joined(separator: ", "))")
        if let r = attr(area, kAXSelectedTextRangeAttribute) { var cr = CFRange(); AXValueGetValue(r as! AXValue, .cfRange, &cr); print("  selection range: \(cr.location),\(cr.length)") }
        if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { print("  last non-empty line (truncated): \(last.prefix(50))") }
    }
}

// 2. Chromium (Helium): does AXManualAccessibility open web content?
if let p = pid("net.imput.helium") {
    let app = AXUIElementCreateApplication(p)
    AXUIElementSetMessagingTimeout(app, 1)
    let w = attr(app, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
    var n = 0, c = 0; if let w { count(w, &n, &c, deadline: DispatchTime.now().uptimeNanoseconds + 2_000_000_000) }
    print("Helium before: \(n) elements, \(c) chars")
    let err = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    print("  set AXManualAccessibility -> \(err.rawValue)")
    usleep(800_000)
    let t = DispatchTime.now().uptimeNanoseconds
    n = 0; c = 0; if let w { count(w, &n, &c, deadline: DispatchTime.now().uptimeNanoseconds + 3_000_000_000) }
    print("Helium after AXManualAccessibility: \(n) elements, \(c) chars, walk \(ms(t))")
    if let w, let web = find(w, role: "AXWebArea") {
        print("  AXWebArea found; parameterized: \(pnames(web).filter { $0.contains("Marker") || $0.contains("Range") }.prefix(8).joined(separator: ", "))")
        print("  AXSelectedTextMarkerRange present: \(attr(web, "AXSelectedTextMarkerRange") != nil)")
    }
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanFalse)
}

// 3. Menu bars: how many actionable commands does each app expose?
for bundle in ["com.mitchellh.ghostty", "com.anthropic.claudefordesktop", "net.imput.helium", "com.t3tools.t3code", "com.apple.finder", "com.apple.dt.Xcode", "net.whatsapp.WhatsApp"] {
    guard let p = pid(bundle) else { continue }
    let app = AXUIElementCreateApplication(p)
    AXUIElementSetMessagingTimeout(app, 0.5)
    let t = DispatchTime.now().uptimeNanoseconds
    var items = 0, enabled = 0, withShortcut = 0
    func walk(_ e: AXUIElement, _ d: Int) {
        guard d < 8 else { return }
        for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if (attr(c, kAXRoleAttribute) as? String) == "AXMenuItem", let title = attr(c, kAXTitleAttribute) as? String, !title.isEmpty {
                items += 1
                if (attr(c, kAXEnabledAttribute) as? Bool) == true { enabled += 1 }
                if attr(c, "AXMenuItemCmdChar") as? String != nil { withShortcut += 1 }
            }
            walk(c, d + 1)
        }
    }
    if let bar = attr(app, kAXMenuBarAttribute) { walk(bar as! AXUIElement, 0) }
    print("menu bar \(bundle): \(items) items (\(enabled) enabled, \(withShortcut) with shortcuts) in \(ms(t))")
}

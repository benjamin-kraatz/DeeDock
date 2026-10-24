import AppKit
import ApplicationServices
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func pnames(_ e: AXUIElement) -> [String] { var n: CFArray?; AXUIElementCopyParameterizedAttributeNames(e, &n); return (n as? [String]) ?? [] }
func count(_ e: AXUIElement, _ n: inout Int, _ chars: inout Int, deadline: UInt64) {
    if n > 8000 || DispatchTime.now().uptimeNanoseconds > deadline { return }
    n += 1
    for k in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] { if let s = attr(e, k) as? String { chars += s.count } }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { count(c, &n, &chars, deadline: deadline) }
}
func find(_ e: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
    if (attr(e, kAXRoleAttribute) as? String) == role { return e }
    if depth > 20 { return nil }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, role: role, depth: depth + 1) { return f } }
    return nil
}
let p = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first!.processIdentifier
let app = AXUIElementCreateApplication(p)
AXUIElementSetMessagingTimeout(app, 1)
let w = attr(app, kAXFocusedWindowAttribute).map { $0 as! AXUIElement } ?? (attr(app, kAXWindowsAttribute) as! [AXUIElement]).first!
let before = attr(app, "AXEnhancedUserInterface") as? Bool
print("AXEnhancedUserInterface before: \(String(describing: before))")
let err = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
print("set -> \(err.rawValue)")
var n = 0, c = 0
for _ in 0..<6 {
    usleep(500_000); n = 0; c = 0
    count(w, &n, &c, deadline: DispatchTime.now().uptimeNanoseconds + 3_000_000_000)
    if n > 100 { break }
}
print("after: \(n) elements, \(c) chars")
if let web = find(w, role: "AXWebArea") {
    print("AXWebArea: url=\((attr(web, "AXURL") as? URL)?.host ?? "?") marker APIs: \(pnames(web).filter { $0.contains("TextMarker") }.count)  AXSelectedTextMarkerRange=\(attr(web, "AXSelectedTextMarkerRange") != nil)")
}
AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, (before ?? false) ? kCFBooleanTrue : kCFBooleanFalse)
print("restored to \(before ?? false)")

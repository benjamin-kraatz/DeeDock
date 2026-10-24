// Cross-process AX selection read + replace against our throwaway target only.
import AppKit
import ApplicationServices
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func find(_ e: AXUIElement, _ role: String) -> AXUIElement? {
    if (attr(e, kAXRoleAttribute) as? String) == role { return e }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, role) { return f } }
    return nil
}
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
let window = (attr(app, kAXWindowsAttribute) as! [AXUIElement])[0]
let text = find(window, "AXTextArea")!
var range = CFRange(location: 4, length: 11)   // "quick brown"
AXUIElementSetAttributeValue(text, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &range)!)
print("selected:", attr(text, kAXSelectedTextAttribute) as? String ?? "nil")
var bounds: CFTypeRef?
AXUIElementCopyParameterizedAttributeValue(text, kAXBoundsForRangeParameterizedAttribute as CFString, AXValueCreate(.cfRange, &range)!, &bounds)
var rect = CGRect.zero; if let bounds { AXValueGetValue(bounds as! AXValue, .cgRect, &rect) }
print("selection on screen (for highlighting):", rect.integral)
let err = AXUIElementSetAttributeValue(text, kAXSelectedTextAttribute as CFString, "slow red" as CFString)
print("replace ->", err.rawValue, "| value now:", (attr(text, kAXValueAttribute) as? String ?? "").prefix(40))
var undoProbe: CFArray?; AXUIElementCopyActionNames(text, &undoProbe); print("text actions:", undoProbe as? [String] ?? [])

import AppKit
import ApplicationServices
_ = NSApplication.shared
let pid = pid_t(CommandLine.arguments[1])!
let previous = NSWorkspace.shared.frontmostApplication
let savedCursor = CGEvent(source: nil)!.location
func bounds(_ id: CGWindowID) -> CGRect? {
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
    guard let a = CFArrayCreate(nil, &ids, 1, nil), let d = (CGWindowListCreateDescriptionFromArray(a) as? [[String: Any]])?.first,
          let b = d[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}
let frame = bounds(CGWindowID(CommandLine.arguments[2])!)!
let click = CGPoint(x: frame.minX + 300, y: frame.minY + 14)
let msrc = CGEventSource(stateID: .hidSystemState)
for type in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: msrc, mouseType: type, mouseCursorPosition: click, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(40_000) }
CGWarpMouseCursorPosition(savedCursor)
usleep(700_000); print("after click: target active =", NSRunningApplication(processIdentifier: pid)?.isActive ?? false)
print("target active before lab:", NSRunningApplication(processIdentifier: pid)?.isActive ?? false)
let lab = Process(); lab.executableURL = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/../lab/CompanionLabBin")
lab.environment = ["LAB_TARGET_PID": String(pid), "LAB_DEMO": "focus"]
let pipe = Pipe(); lab.standardOutput = pipe
try! lab.run()
usleep(1_300_000)
guard NSRunningApplication(processIdentifier: pid)?.isActive == true else { print("target lost focus before typing; abort"); lab.terminate(); previous?.activate(); exit(1) }
let src = CGEventSource(stateID: .privateState)
for key: CGKeyCode in [4, 34] { for down in [true, false] { CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)?.post(tap: .cghidEventTap); usleep(30_000) } }
usleep(2_200_000)
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
let window = (attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement])?.first
var value = ""
func scan(_ e: AXUIElement) { if (attr(e, kAXRoleAttribute) as? String) == "AXTextArea" { value = attr(e, kAXValueAttribute) as? String ?? "" }; for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { scan(c) } }
if let window { scan(window) }
print("target text starts with:", value.prefix(12), "| target still active:", NSRunningApplication(processIdentifier: pid)?.isActive ?? false)
lab.terminate(); lab.waitUntilExit()
print(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.split(separator: "\n").filter { $0.contains("focus") || $0.contains("prompt:") || $0.contains("dismiss") }.joined(separator: "\n"))
previous?.activate()

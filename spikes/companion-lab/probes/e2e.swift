import AppKit
_ = NSApplication.shared
func bounds(_ id: CGWindowID) -> CGRect? {
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
    guard let a = CFArrayCreate(nil, &ids, 1, nil), let d = (CGWindowListCreateDescriptionFromArray(a) as? [[String: Any]])?.first,
          let b = d[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}
let pid = pid_t(CommandLine.arguments[1])!
let wid = CGWindowID(CommandLine.arguments[2])!
let saved = CGEvent(source: nil)!.location
let src = CGEventSource(stateID: .hidSystemState)
var last = saved
func guardCursor() { let c = CGEvent(source: nil)!.location; if hypot(c.x - last.x, c.y - last.y) > 3 { print("ABORT: cursor moved by user"); CGWarpMouseCursorPosition(saved); exit(2) } }
func mouse(_ type: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap); last = p }
func move(to p: CGPoint, steps: Int = 8) { let a = last; for i in 1...steps { guardCursor(); mouse(.mouseMoved, CGPoint(x: a.x + (p.x - a.x) * CGFloat(i) / CGFloat(steps), y: a.y + (p.y - a.y) * CGFloat(i) / CGFloat(steps))); usleep(16_000) } }
func click(_ p: CGPoint) { move(to: p); mouse(.leftMouseDown, p); usleep(50_000); mouse(.leftMouseUp, p) }
func key(_ code: CGKeyCode) { for down in [true, false] { CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap); usleep(25_000) } }
func pump(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

let f = bounds(wid)!
last = saved
click(CGPoint(x: f.minX + 300, y: f.minY + 14)); pump(0.6)
guard NSRunningApplication(processIdentifier: pid)?.isActive == true else { print("target not active; abort"); CGWarpMouseCursorPosition(saved); exit(1) }
let tab = CGPoint(x: f.midX, y: f.minY - 20)
move(to: tab, steps: 12); pump(0.5)                         // hover → awake
mouse(.leftMouseDown, tab); usleep(50_000); mouse(.leftMouseUp, tab); pump(0.7)   // click → selection
let a = CGPoint(x: f.minX + 12, y: f.minY + 36), b = CGPoint(x: f.minX + 470, y: f.minY + 60)
move(to: a); mouse(.leftMouseDown, a)
for i in 1...20 { guardCursor(); mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * CGFloat(i) / 20, y: a.y + (b.y - a.y) * CGFloat(i) / 20)); usleep(16_000) }
mouse(.leftMouseUp, b); pump(1.0)
for k: CGKeyCode in [14, 7, 35, 37, 0, 34, 45] { key(k) }    // "explain"
key(36); pump(6.5)                                           // Return → answer
let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
shot.arguments = ["-x", "-R\(Int(f.minX - 60)),\(Int(f.minY - 70)),\(Int(f.width + 120)),440", "e2e-answer.png"]
try? shot.run(); shot.waitUntilExit()
key(53); pump(0.6)                                           // Esc → Done
CGWarpMouseCursorPosition(saved)
print("e2e finished")

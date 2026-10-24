// Drags our throwaway target window and measures how far the lab's tab trails it, from the window
// server's own bounds for both windows. Aborts on any keyboard input or if the cursor leaves our path.
import AppKit
func bounds(_ id: CGWindowID) -> CGRect? {
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
    guard let a = CFArrayCreate(nil, &ids, 1, nil), let d = (CGWindowListCreateDescriptionFromArray(a) as? [[String: Any]])?.first,
          let b = d[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}
_ = NSApplication.shared
let targetWID = CGWindowID(CommandLine.arguments[1])!
let labPID = Int32(CommandLine.arguments[2])!
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let panelWID = info.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == labPID })?[kCGWindowNumber as String] as? CGWindowID else { print("no lab panel"); exit(1) }
let previous = NSWorkspace.shared.frontmostApplication
let saved = CGEvent(source: nil)!.location
let start = bounds(targetWID)!
let grab = CGPoint(x: start.minX + 160, y: start.minY + 14)
let src = CGEventSource(stateID: .privateState)
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
var errors: [CGFloat] = []
var aborted = false
let t0 = Date()
post(.leftMouseDown, grab)
let sampler = Timer.scheduledTimer(withTimeInterval: 1.0 / 240, repeats: true) { _ in
    guard let w = bounds(targetWID), let p = bounds(panelWID) else { return }
    errors.append(abs(p.midX - w.midX))
}
RunLoop.main.add(sampler, forMode: .common)
var step = 0
Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
    step += 1
    let p = CGPoint(x: grab.x + CGFloat(step * 6), y: grab.y + CGFloat(step))
    let cursor = CGEvent(source: nil)!.location
    let expected = CGPoint(x: grab.x + CGFloat((step - 1) * 6), y: grab.y + CGFloat(step - 1))
    if CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < Date().timeIntervalSince(t0) || (step > 1 && hypot(cursor.x - expected.x, cursor.y - expected.y) > 3) { aborted = true }
    post(.leftMouseDragged, p)
    if step == 90 || aborted {
        t.invalidate()
        post(.leftMouseUp, p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            sampler.invalidate()
            CGWarpMouseCursorPosition(saved)
            previous?.activate()
            let during = errors.dropLast(60).sorted()   // the final 0.25 s is the settle period
            let settled = errors.suffix(10).max() ?? -1
            let speed: CGFloat = 6 * 60   // points per second horizontally
            if aborted { print("ABORTED") }
            print(String(format: "trailing distance: p50 %.1fpt p95 %.1fpt max %.1fpt (≈ %.0f / %.0f ms at %.0f pt/s); after release %.1fpt",
                         during[during.count / 2], during[during.count * 95 / 100], during.last ?? -1,
                         during[during.count / 2] / speed * 1000, during[during.count * 95 / 100] / speed * 1000, speed, settled))
            exit(0)
        }
    }
}
NSApplication.shared.run()

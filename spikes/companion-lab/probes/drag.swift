// Live title-bar drag of our own throwaway window; measures how fresh each tracking signal is.
import AppKit
import ApplicationServices

typealias ConnProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func sym<T>(_ n: String, _: T.Type) -> T? { dlsym(sky, n).map { unsafeBitCast($0, to: T.self) } }
let SLSMainConnectionID = sym("SLSMainConnectionID", (@convention(c) () -> Int32).self)!
let SLSRegisterConnectionNotifyProc = sym("SLSRegisterConnectionNotifyProc", (@convention(c) (Int32, ConnProc, UInt32, UnsafeMutableRawPointer?) -> Int32).self)!
let SLSRequestNotificationsForWindows = sym("SLSRequestNotificationsForWindows", (@convention(c) (Int32, UnsafePointer<UInt32>, Int32) -> Int32).self)!

let any = CGEventType(rawValue: ~0)!
func hwIdle() -> Double { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any) }
let t0 = DispatchTime.now().uptimeNanoseconds
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 }

let targetPID = pid_t(CommandLine.arguments[1])!
var wid = UInt32(CommandLine.arguments[2])!
func cgBounds() -> CGRect? {
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(wid))]
    let array = CFArrayCreate(nil, &ids, 1, nil)
    guard let d = (CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]])?.first,
          let b = d[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}
struct Obs { let t: Double; let x: CGFloat }
var ax: [Obs] = [], sls: [Obs] = [], poll: [Obs] = [], posts: [(t: Double, x: CGFloat)] = []

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)
let previous = NSWorkspace.shared.frontmostApplication
let savedCursor = CGEvent(source: nil)!.location

let cid = SLSMainConnectionID()
_ = SLSRegisterConnectionNotifyProc(cid, { type, _, _, _, _ in
    if let b = cgBounds() { sls.append(Obs(t: now(), x: b.minX)) }
}, 806, nil)
_ = SLSRequestNotificationsForWindows(cid, &wid, 1)

let axApp = AXUIElementCreateApplication(targetPID)
var ws: CFTypeRef?
for _ in 0..<20 where ws == nil {
    AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ws)
    if (ws as? [AXUIElement])?.isEmpty ?? true { ws = nil; usleep(100_000) }
}
guard let axWin = (ws as? [AXUIElement])?.first else { print("no AX window for target"); exit(1) }
var observer: AXObserver?
AXObserverCreate(targetPID, { _, el, _, _ in
    var p: CFTypeRef?; AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p)
    var pt = CGPoint.zero; if let p { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
    ax.append(Obs(t: now(), x: pt.x))
}, &observer)
AXObserverAddNotification(observer!, axWin, kAXMovedNotification as CFString, nil)
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer!), .commonModes)

var cost: [Double] = []
for _ in 0..<300 { let s = DispatchTime.now().uptimeNanoseconds; _ = cgBounds(); cost.append(Double(DispatchTime.now().uptimeNanoseconds - s) / 1000) }
cost.sort(); print(String(format: "one-window bounds read: p50 %.0fµs p95 %.0fµs", cost[150], cost[285]))
guard let start = cgBounds() else { print("no CG bounds"); exit(1) }
let grab = CGPoint(x: start.midX, y: start.minY + 14)   // title bar, top-left-origin global coordinates
let src = CGEventSource(stateID: .privateState)
func post(_ type: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }

var lastPoll: CGFloat = start.minX
Timer.scheduledTimer(withTimeInterval: 1.0 / 240, repeats: true) { _ in
    if let b = cgBounds(), b.minX != lastPoll { lastPoll = b.minX; poll.append(Obs(t: now(), x: b.minX)) }
}

var step = 0
var aborted = false
let testStart = now()
post(.leftMouseDown, grab)
Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
    let keyIdle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    let cursor = CGEvent(source: nil)!.location
    let expected = CGPoint(x: grab.x + CGFloat(step * 6), y: grab.y)
    if keyIdle * 1000 < now() - testStart || hypot(cursor.x - expected.x, cursor.y - expected.y) > 3 { aborted = true }
    step += 1
    let p = CGPoint(x: grab.x + CGFloat(step * 6), y: grab.y)
    posts.append((now(), start.minX + CGFloat(step * 6)))
    post(.leftMouseDragged, p)
    if step == 60 || aborted {
        t.invalidate()
        post(.leftMouseUp, p)
        CGWarpMouseCursorPosition(savedCursor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            previous?.activate()
            func report(_ name: String, _ o: [Obs]) {
                // latency = time we first saw an x minus the time that x was requested
                var lat: [Double] = []
                var seen = Set<CGFloat>()
                for ob in o where !seen.contains(ob.x) {
                    seen.insert(ob.x)
                    if let req = posts.first(where: { $0.x == ob.x }) { lat.append(ob.t - req.t) }
                }
                lat.sort()
                let during = o.filter { ob in ob.t <= (posts.last?.t ?? 0) }.count
                print(String(format: "%@: %d callbacks (%d during drag), %d distinct positions, latency p50 %.1fms p90 %.1fms",
                             name, o.count, during, seen.count, lat.isEmpty ? -1 : lat[lat.count / 2], lat.isEmpty ? -1 : lat[min(lat.count - 1, lat.count * 9 / 10)]))
            }
            print(aborted ? "ABORTED: user input detected" : "60 drag events over ~1s")
            report("AX kAXMovedNotification", ax)
            report("SkyLight 806 + CGWindowList", sls)
            report("CGWindowList poll @240Hz", poll)
            exit(0)
        }
    }
}
NSApplication.shared.run()

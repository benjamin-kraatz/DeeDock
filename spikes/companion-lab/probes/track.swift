// Discovers which SkyLight connection notifications fire for a foreign window, and how fresh AX/CGWindowList are.
import AppKit
import ApplicationServices

typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
typealias ConnProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func sym<T>(_ n: String, _: T.Type) -> T? { dlsym(sky, n).map { unsafeBitCast($0, to: T.self) } }
let SLSMainConnectionID = sym("SLSMainConnectionID", (@convention(c) () -> Int32).self)!
let SLSRegisterNotifyProc = sym("SLSRegisterNotifyProc", (@convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32).self)
let SLSRequestNotificationsForWindows = sym("SLSRequestNotificationsForWindows", (@convention(c) (Int32, UnsafePointer<UInt32>, Int32) -> Int32).self)
let SLSRegisterConnectionNotifyProc = sym("SLSRegisterConnectionNotifyProc", (@convention(c) (Int32, ConnProc, UInt32, UnsafeMutableRawPointer?) -> Int32).self)
print("SLSRegisterNotifyProc:", SLSRegisterNotifyProc != nil, " SLSRequestNotificationsForWindows:", SLSRequestNotificationsForWindows != nil)

let t0 = DispatchTime.now().uptimeNanoseconds
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 }
var slsCounts: [UInt32: Int] = [:]
var slsFirst: [UInt32: Double] = [:]
let proc: NotifyProc = { type, data, len, _ in
    slsCounts[type, default: 0] += 1
    if slsFirst[type] == nil { slsFirst[type] = now() }
}

_ = NSApplication.shared
let targetPID = pid_t(CommandLine.arguments[1])!
var wid = UInt32(CommandLine.arguments[2])!
let cid = SLSMainConnectionID()
var registered: [UInt32] = []
let cproc: ConnProc = { type, _, _, _, _ in
    slsCounts[type, default: 0] += 1
    if slsFirst[type] == nil { slsFirst[type] = now() }
}
for type in UInt32(700)...UInt32(1500) {
    if SLSRegisterNotifyProc?(proc, type, nil) == 0 { registered.append(type) }
    _ = SLSRegisterConnectionNotifyProc?(cid, cproc, type, nil)
}
print("registered \(registered.count) event types")
print("request windows:", SLSRequestNotificationsForWindows?(cid, &wid, 1) ?? -1)

var axMoves = 0
let axApp = AXUIElementCreateApplication(targetPID)
var win: CFTypeRef?
AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &win)
if win == nil { var ws: CFTypeRef?; AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ws); win = (ws as? [AXUIElement])?.first }
let axWin = win as! AXUIElement
var observer: AXObserver?
AXObserverCreate(targetPID, { _, _, _, _ in axMoves += 1 }, &observer)
AXObserverAddNotification(observer!, axWin, kAXMovedNotification as CFString, nil)
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer!), .defaultMode)

// Cost of reading one window's live bounds from the window server (what a display-link poll would do).
var samples: [Double] = []
for _ in 0..<500 {
    let s = DispatchTime.now().uptimeNanoseconds
    _ = CGWindowListCreateDescriptionFromArray([NSNumber(value: wid)] as CFArray)
    samples.append(Double(DispatchTime.now().uptimeNanoseconds - s) / 1000)
}
samples.sort()
print(String(format: "CGWindowListCreateDescriptionFromArray(1 window): p50 %.0fµs p95 %.0fµs", samples[250], samples[475]))

// Move the target window programmatically through AX 60×/s for one second and count signals.
var step = 0
let start = CGPoint(x: 300, y: 300)
Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
    step += 1
    var p = CGPoint(x: start.x + CGFloat(step * 4), y: start.y)
    AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    if step == 60 {
        t.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            print("AX kAXMovedNotification callbacks: \(axMoves) for 60 programmatic moves")
            for (k, v) in slsCounts.sorted(by: { $0.key < $1.key }) { print("SLS event \(k): \(v)× first at \(String(format: "%.0f", slsFirst[k]!))ms") }
            exit(0)
        }
    }
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

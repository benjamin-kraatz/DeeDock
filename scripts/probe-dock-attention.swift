// Standalone finite diagnostic sampler. Compile with swiftc; do not add to an app target.
// Reads only Rattention Dock items. Requires existing AX access and never prompts for it.
// Deliberately records all attributes for investigation, not for production polling.
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}
func names(_ element: AXUIElement) -> [String] {
    var result: CFArray?
    AXUIElementCopyAttributeNames(element, &result)
    return result as? [String] ?? []
}
let start = Date()
func log(_ text: String) { print(String(format: "%.3f", Date().timeIntervalSince(start)), text); fflush(stdout) }
guard AXIsProcessTrusted() else { print("AX_NOT_TRUSTED"); exit(2) }
guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { exit(3) }
let root = AXUIElementCreateApplication(dock.processIdentifier)
AXUIElementSetMessagingTimeout(root, 0.2)
let lists = value(root, "AXChildren") as? [AXUIElement] ?? []
let items = lists.flatMap { value($0, "AXChildren") as? [AXUIElement] ?? [] }
let matches = items.filter { (value($0, "AXTitle") as? String ?? "").contains("Rattention") }
log("MATCHES \(matches.count)")
var observer: AXObserver?
AXObserverCreate(dock.processIdentifier, { _, element, notification, _ in
    log("EVENT \(notification) title=\(value(element, "AXTitle").map { String(describing: $0) } ?? "nil")")
}, &observer)
let notifications = ["AXMoved", "AXResized", "AXValueChanged", "AXTitleChanged", "AXLayoutChanged", "AXSelectedChildrenChanged", "AXUIElementDestroyed", "AXCreated", "AXAnnouncementRequested"]
for (index, item) in matches.enumerated() {
    AXUIElementSetMessagingTimeout(item, 0.1)
    log("ITEM \(index) ATTRIBUTES \(names(item))")
    var parameterized: CFArray?
    AXUIElementCopyParameterizedAttributeNames(item, &parameterized)
    log("PARAMETERIZED \(String(describing: parameterized))")
    if let observer {
        for n in notifications { log("SUBSCRIBE \(index) \(n) \(AXObserverAddNotification(observer, item, n as CFString, nil).rawValue)") }
    }
}
if let observer { CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes) }
var previous: [String: String] = [:]
var samples = 0
var lastFront: pid_t = -1
let duration = Double(CommandLine.arguments.dropFirst().first ?? "40") ?? 40
while Date().timeIntervalSince(start) < duration {
    for (index, item) in matches.enumerated() {
        for name in names(item) {
            let key = "\(index).\(name)"
            let current = value(item, name).map { String(describing: $0).replacingOccurrences(of: "0x[0-9a-f]+", with: "PTR", options: .regularExpression) } ?? "<nil>"
            if previous[key] != current { log("CHANGE \(key) \(current)"); previous[key] = current }
        }
    }
    let front = NSWorkspace.shared.frontmostApplication
    if front?.processIdentifier != lastFront { log("FRONT \(front?.localizedName ?? "nil") pid=\(front?.processIdentifier ?? -1)"); lastFront = front?.processIdentifier ?? -1 }
    samples += 1
    RunLoop.current.run(until: Date().addingTimeInterval(0.025))
}
log("DONE samples=\(samples)")

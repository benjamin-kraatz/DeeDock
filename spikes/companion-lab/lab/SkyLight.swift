import ApplicationServices
import CoreGraphics
import Foundation

/// dlsym bridge to the private SkyLight calls this spike evaluates. Every symbol is optional so the
/// lab degrades to public AX tracking when one disappears.
enum SkyLight {
    typealias ConnectionProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static func symbol<T>(_ name: String, _: T.Type) -> T? { dlsym(handle, name).map { unsafeBitCast($0, to: T.self) } }

    static let mainConnection = symbol("SLSMainConnectionID", (@convention(c) () -> Int32).self)
    static let registerConnectionNotify = symbol("SLSRegisterConnectionNotifyProc", (@convention(c) (Int32, ConnectionProc, UInt32, UnsafeMutableRawPointer?) -> Int32).self)
    static let requestNotifications = symbol("SLSRequestNotificationsForWindows", (@convention(c) (Int32, UnsafePointer<UInt32>, Int32) -> Int32).self)

    /// Measured on macOS 27 with this lab: 806 fires per window-server move step, 807 per resize step.
    static let windowMoved: UInt32 = 806
    static let windowResized: UInt32 = 807
}

/// Private but long-stable (AltTab, Rectangle, Hammerspoon): maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var flag: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] { (copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
}

/// Live window-server bounds for one window in top-left global points. ~80 µs per call.
func windowServerBounds(_ id: CGWindowID) -> CGRect? {
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
    guard let array = CFArrayCreate(nil, &ids, 1, nil),
          let info = (CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]])?.first,
          let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: bounds as CFDictionary)
}

func lab(_ message: String) {
    let stamp = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
    print("[lab \(stamp)] \(message)")
    fflush(stdout)
}

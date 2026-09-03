import Foundation

/// Pure display/application fixtures, independent of the host's actual hardware or applications.
enum DisplayFixtures {
    static func screen(_ name: String, runtimeID: UInt32, x: CGFloat = 0, primary: Bool = false,
                       mirror: UInt32? = nil, persistent: Bool = true) -> DisplaySnapshot {
        let frame = CGRect(x: x, y: -200, width: 1600, height: 1000)
        return DisplaySnapshot(id: "\(persistent ? "display" : "session").\(name)", runtimeID: runtimeID, name: name,
                               isPersistent: persistent, isPrimary: primary, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 40),
                               mirrorSource: mirror, isDrawable: true)
    }
    static func app(_ id: String) -> ApplicationReference {
        ApplicationReference(bundleIdentifier: id, url: URL(fileURLWithPath: "/Fixtures/\(id).app"), name: id)
    }
}

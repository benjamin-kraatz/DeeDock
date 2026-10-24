import AppKit

/// Window-server notifications for one window of another app: moved (806) and resized (807).
///
/// SkyLight is private. The three calls were verified with probes on macOS 27.0: a normal
/// process with SIP on receives one notification per step of another app's live title-bar drag
/// (about 23 ms after the input), where AX `kAXMovedNotification` arrives at about 10 Hz. The
/// event numbers come from reverse engineering (AltTab and JankyBorders agree on them), and
/// `dlsym` proves only that a symbol exists, not its signature, so the interface is gated to
/// macOS 27 exactly like `LaunchServicesBackgroundReader`. Re-verify before widening the gate.
/// When it is unavailable, Robi falls back to AX notifications plus drag prediction.
@MainActor
final class RobiWindowServerEvents {
    private typealias ConnectionProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void

    private struct Interface {
        let connection: Int32
        let register: @convention(c) (Int32, ConnectionProc, UInt32, UnsafeMutableRawPointer?) -> Int32
        let request: @convention(c) (Int32, UnsafePointer<UInt32>, Int32) -> Int32

        static func resolve() -> Interface? {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
                  let image = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
                  let main = dlsym(image, "SLSMainConnectionID"),
                  let register = dlsym(image, "SLSRegisterConnectionNotifyProc"),
                  let request = dlsym(image, "SLSRequestNotificationsForWindows") else { return nil }
            let connection = unsafeBitCast(main, to: (@convention(c) () -> Int32).self)()
            return Interface(connection: connection,
                             register: unsafeBitCast(register, to: (@convention(c) (Int32, ConnectionProc, UInt32, UnsafeMutableRawPointer?) -> Int32).self),
                             request: unsafeBitCast(request, to: (@convention(c) (Int32, UnsafePointer<UInt32>, Int32) -> Int32).self))
        }
    }

    private static let moved: UInt32 = 806
    private static let resized: UInt32 = 807
    private static let interface = Interface.resolve()
    /// SkyLight offers no unregister call, so the process registers once and routes to whichever
    /// instance is currently listening.
    private static var registered = false
    private static weak var listener: RobiWindowServerEvents?

    /// Called on the main thread for every move or resize step of the watched window.
    var changed: (() -> Void)?

    var isAvailable: Bool { Self.interface != nil }

    func start() {
        guard let interface = Self.interface else { return }
        Self.listener = self
        guard !Self.registered else { return }
        Self.registered = true
        for event in [Self.moved, Self.resized] {
            _ = interface.register(interface.connection, { _, _, _, _, _ in
                // Delivered through the main run loop's window-server port; hop if that ever changes.
                if Thread.isMainThread {
                    MainActor.assumeIsolated { RobiWindowServerEvents.listener?.changed?() }
                } else {
                    Task { @MainActor in RobiWindowServerEvents.listener?.changed?() }
                }
            }, event, nil)
        }
    }

    /// Replaces the watched window. SkyLight keeps one subscription list per connection, so this
    /// also drops the previous window.
    func watch(_ windowID: CGWindowID?) {
        guard let interface = Self.interface else { return }
        _ = withUnsafePointer(to: windowID ?? 0) { id in
            interface.request(interface.connection, id, windowID == nil ? 0 : 1)
        }
    }

    func stop() {
        watch(nil)
        changed = nil
        if Self.listener === self { Self.listener = nil }
    }
}

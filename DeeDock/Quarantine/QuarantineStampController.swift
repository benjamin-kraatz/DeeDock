import AppKit
import Observation

/// Owns one transient stamp mode and a pointer-following overlay across applications;
/// no cursor hiding, cursor stack pushes, event taps, or system preferences are involved.
@MainActor @Observable
final class QuarantineStampController {
    static let modeChanged = Notification.Name("DDock.quarantineStampModeChanged")
    static let shared = QuarantineStampController()
    private let preferences: UserDefaults? = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" ? nil : .standard
    }()

    var enabled = false {
        didSet {
            preferences?.set(enabled, forKey: "quarantine.enabled.v1")
            if !enabled { disarm() }
        }
    }
    var armSound = true { didSet { preferences?.set(armSound, forKey: "quarantine.sound.arm.v1"); if !armSound { sounds["arm"]?.stop() } } }
    var stampSound = true { didSet { preferences?.set(stampSound, forKey: "quarantine.sound.stamp.v1"); if !stampSound { sounds["stamp"]?.stop() } } }
    var releaseSound = true { didSet { preferences?.set(releaseSound, forKey: "quarantine.sound.undo.v1"); if !releaseSound { sounds["undo"]?.stop() } } }

    private init() {
        enabled = preferences?.bool(forKey: "quarantine.enabled.v1") ?? false
        armSound = preferences?.object(forKey: "quarantine.sound.arm.v1") as? Bool ?? true
        stampSound = preferences?.object(forKey: "quarantine.sound.stamp.v1") as? Bool ?? true
        releaseSound = preferences?.object(forKey: "quarantine.sound.undo.v1") as? Bool ?? true
    }
    private(set) var armed = false
    private(set) var frame = "QuarantineIdle"
    private var monitor: Any?
    private var globalPointerMonitor: Any?
    private var cursorOverlay: QuarantineCursorOverlay?
    private let stampTargets = NSHashTable<NSView>.weakObjects()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var feedbackTask: Task<Void, Never>?
    private var sounds: [String: NSSound] = [:]

    /// Native item targets register weakly so scrolling, removed views, and closed panels
    /// cannot leave stale regions that claim to accept a stamp.
    func registerTarget(_ view: NSView) {
        stampTargets.add(view)
        cursorOverlay?.register(view)
    }

    func unregisterTarget(_ view: NSView) {
        stampTargets.remove(view)
        cursorOverlay?.unregister(view)
    }

    func toggle() { armed ? disarm() : arm() }

    private func arm() {
        guard enabled, !QuarantineStore.shared.unreadable else { return }
        armed = true
        NotificationCenter.default.post(name: Self.modeChanged, object: self)
        frame = "QuarantineIdle"
        cursorOverlay = QuarantineCursorOverlay()
        cursorOverlay?.show(frame: frame)
        for target in stampTargets.allObjects { cursorOverlay?.register(target) }
        play("arm")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            guard let self, self.armed else { return event }
            if event.type == .rightMouseDown || (event.type == .keyDown && event.keyCode == 53) {
                self.disarm()
                return nil
            }
            self.cursorOverlay?.move()
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            guard let self, self.armed else { return }
            // Global mouse monitoring requires no keyboard permission. It observes the
            // outside click without suppressing the other application's context menu.
            if event.type == .rightMouseDown {
                self.disarm()
                return
            }
            self.cursorOverlay?.move()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification)
        observe(NotificationCenter.default, NSApplication.willTerminateNotification)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.disarm() }
        }
        observers.append((center, token))
    }

    func disarm() {
        let wasArmed = armed
        armed = false
        if wasArmed { NotificationCenter.default.post(name: Self.modeChanged, object: self) }
        feedbackTask?.cancel()
        feedbackTask = nil
        frame = "QuarantineIdle"
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        globalPointerMonitor = nil
        cursorOverlay?.close()
        cursorOverlay = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    /// Commits first. Failed persistence must never play a successful stamp effect.
    func stamp(id: String, url: URL, name: String) {
        guard armed else { return }
        guard let change = QuarantineStore.shared.toggle(id: id, url: url, name: name) else { return }
        feedback(releasing: change == .released)
    }

    func release(_ record: QuarantineStore.Record) {
        guard armed else { return }
        guard QuarantineStore.shared.release(record) else { return }
        feedback(releasing: true)
    }

    private func feedback(releasing: Bool) {
        play(releasing ? "undo" : "stamp")
        feedbackTask?.cancel()
        guard armed else { return }
        frame = "QuarantinePress"
        cursorOverlay?.show(frame: frame)
        feedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(110))
                guard let self, self.armed else { return }
                self.frame = "QuarantineIdle"
                self.cursorOverlay?.show(frame: self.frame)
            } catch { }
        }
    }

    private func play(_ role: String) {
        guard enabled else { return }
        let allowed = role == "arm" ? armSound : role == "stamp" ? stampSound : releaseSound
        guard allowed else { return }
        playSound(role)
    }

    /// Plays one feedback sound for Settings, even when its toggle is off, so a user can hear
    /// it before deciding. `role` is `"arm"`, `"stamp"`, or `"undo"`.
    func preview(_ role: String) { playSound(role) }

    private func playSound(_ role: String) {
        if sounds[role] == nil,
           let url = Bundle.main.url(forResource: "quarantine_stamp_\(role)", withExtension: "wav") {
            sounds[role] = NSSound(contentsOf: url, byReference: false)
        }
        sounds[role]?.stop()
        // NSSound uses the system output volume/mute. DDock has no existing Focus audio gate.
        sounds[role]?.play()
    }
}

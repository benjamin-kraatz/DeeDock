import AppKit
import Carbon

/// The global Option-Shift-Command-R shortcut that wakes Robi on the focused window.
///
/// Same mechanism as Radar's and Find a Window's shortcuts: a Carbon hot key on the application
/// event target, which needs no event-monitor permission. Registration fails when another app owns
/// the combination; Settings then reports the conflict and clicking Robi still works. The handler
/// passes on events with any other ID so the shortcuts sharing the target keep working.
@MainActor
final class RobiShortcut {
    static let keyCode = UInt32(kVK_ANSI_R)
    static let modifiers = UInt32(optionKey | shiftKey | cmdKey)
    private static let signature: OSType = 0x44445352
    private static let identifier: UInt32 = 17

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    var isRegistered: Bool { hotKey != nil }

    @discardableResult
    func start(action: @escaping () -> Void) -> Bool {
        stop()
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                // Literals: a C callback cannot read the main-actor statics.
                id.signature == 0x44445352, id.id == 17
            else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application event handlers on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<RobiShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { stop(); return false }
        let registered = RegisterEventHotKey(Self.keyCode, Self.modifiers,
            EventHotKeyID(signature: Self.signature, id: Self.identifier), GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else { stop(); return false }
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
}

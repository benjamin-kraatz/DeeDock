import AppKit
import Carbon

/// The global shortcut that opens Flix Files at the pointer. Control-Option-Command-F unless changed
/// in Settings.
///
/// Same mechanism as Radar's and Robi's shortcuts: a Carbon hot key on the application event target,
/// which needs no event-monitor permission. Hot-key ID 19 (Radar uses 16 and 18, Robi 17). The
/// handler passes on events with any other ID so the shortcuts sharing the target keep working.
/// Registration fails when another app owns the combination; Settings then shows it and the tile
/// still works.
@MainActor
final class FlixShortcut {
    private static let signature: OSType = 0x44445352
    private static let identifier: UInt32 = 19

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    /// The combination currently held, or nil.
    private(set) var registered: FlixShortcutCombo?

    var isRegistered: Bool { registered != nil }

    /// Registers `combo`, replacing any earlier one.
    /// - Returns: False when the handler could not be installed or another app owns `combo`.
    @discardableResult
    func start(_ combo: FlixShortcutCombo, action: @escaping () -> Void) -> Bool {
        stop()
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                // Literals: a C callback cannot read the main-actor statics.
                id.signature == 0x44445352, id.id == 19
            else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application event handlers on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<FlixShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { stop(); return false }
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.modifiers.carbon,
            EventHotKeyID(signature: Self.signature, id: Self.identifier), GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else { stop(); return false }
        registered = combo
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil; registered = nil
    }
}

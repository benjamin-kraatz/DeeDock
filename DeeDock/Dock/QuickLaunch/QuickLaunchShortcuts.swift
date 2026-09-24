import AppKit
import Carbon

/// Registers Control-Option-1 through Control-Option-0 as system-wide hot keys.
///
/// Carbon hot keys need no Accessibility or Input Monitoring permission, unlike a global key
/// monitor, so turning the feature on never prompts. Registration is exclusive: when another app
/// already owns a combination, that slot is reported in `unavailableSlots` and left alone rather
/// than silently stolen. The handler shares the application event target with
/// `WindowSearchShortcut`, so it declines any hot key whose signature is not its own.
@MainActor
final class QuickLaunchShortcuts {
    /// 'DDQL'. Distinct from Window Search's signature so each handler recognises only its own keys.
    private static let signature: OSType = 0x4444_514C
    private static let modifiers = UInt32(controlKey | optionKey)

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var action: ((Int) -> Void)?
    /// One-based slots whose combination another process had already registered.
    private(set) var unavailableSlots: [Int] = []
    var isActive: Bool { handler != nil }

    /// Installs the handler and registers every slot, replacing an earlier registration.
    ///
    /// - Parameter action: Called on the main actor with the one-based slot that was pressed.
    /// - Returns: False when the event handler could not be installed; no slot is registered then.
    @discardableResult
    func start(action: @escaping (Int) -> Void) -> Bool {
        stop()
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                // Literals, not the main-actor statics: this C callback is nonisolated until it
                // enters `assumeIsolated`. Keep them equal to `signature` and `QuickLaunchSlots.count`.
                id.signature == 0x4444_514C, (1...10).contains(id.id) else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application event handlers on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<QuickLaunchShortcuts>.fromOpaque(context).takeUnretainedValue().action?(Int(id.id))
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { stop(); return false }
        for (index, keyCode) in QuickLaunchSlots.keyCodes.enumerated() {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(keyCode), Self.modifiers,
                EventHotKeyID(signature: Self.signature, id: UInt32(index + 1)), GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference { hotKeys.append(reference) }
            else { unavailableSlots.append(index + 1) }
        }
        return true
    }

    /// Unregisters every hot key and removes the handler. Safe to call when already stopped.
    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        action = nil
        unavailableSlots = []
    }
}

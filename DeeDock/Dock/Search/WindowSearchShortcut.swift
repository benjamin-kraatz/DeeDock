import AppKit
import Carbon

/// App-lifetime Command-Shift-Space registration. Carbon hot keys need no event-monitor permission.
@MainActor
final class WindowSearchShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

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
                id.signature == 0x44445352, id.id == 15 else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application event handlers on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<WindowSearchShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { stop(); return false }
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: 0x44445352, id: 15), GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else { stop(); return false }
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
}

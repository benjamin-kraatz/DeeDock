import AppKit
import Carbon

/// The global shortcuts that open Harbor: Option-Shift-Command-Space, Harbor's own, and
/// Shift-Command-Space, which Find a Window used before Harbor replaced it.
///
/// Carbon hot keys need no event-monitor permission. Each combination registers on its own, so
/// another app owning one leaves the other working; Settings then names the combination that is
/// unavailable, and Harbor stays available from the menu and the dock tile. The handler shares the
/// application event target with Robi's shortcut and passes on events with any other ID.
@MainActor
final class HarborShortcut {
    /// One combination DOKK registers. The raw value is its Carbon hot-key ID.
    nonisolated enum Combination: UInt32, CaseIterable, Sendable {
        /// Option-Shift-Command-Space.
        case primary = 16
        /// Shift-Command-Space. Robi's shortcut uses ID 17.
        case alternate = 18

        var modifiers: UInt32 {
            switch self {
            case .primary: UInt32(optionKey | shiftKey | cmdKey)
            case .alternate: UInt32(shiftKey | cmdKey)
            }
        }
    }

    static let keyCode = UInt32(kVK_Space)
    private static let signature: OSType = 0x44445352

    private var hotKeys: [Combination: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var action: ((Combination) -> Void)?

    /// The combinations DOKK currently holds. A combination another app owns is missing.
    var registered: Set<Combination> { Set(hotKeys.keys) }

    /// Installs the handler and registers every combination not yet held.
    ///
    /// Calling it again retries only the combinations that failed, so the ones already held keep
    /// working without a gap. `action` receives the combination that was pressed.
    /// - Returns: The combinations held afterwards.
    @discardableResult
    func start(action: @escaping (Combination) -> Void) -> Set<Combination> {
        self.action = action
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                    // A literal: a C callback cannot read the main-actor statics.
                    id.signature == 0x44445352,
                    let combination = Combination(rawValue: id.id)
                else { return OSStatus(eventNotHandledErr) }
                // Carbon dispatches application event handlers on the main event loop.
                MainActor.assumeIsolated {
                    Unmanaged<HarborShortcut>.fromOpaque(context).takeUnretainedValue().action?(combination)
                }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard installed == noErr else { stop(); return [] }
        }
        for combination in Combination.allCases where hotKeys[combination] == nil {
            var hotKey: EventHotKeyRef?
            let status = RegisterEventHotKey(Self.keyCode, combination.modifiers,
                EventHotKeyID(signature: Self.signature, id: combination.rawValue), GetApplicationEventTarget(), 0, &hotKey)
            if status == noErr, let hotKey { hotKeys[combination] = hotKey }
        }
        // Holding nothing, the handler would only sit in the event path.
        if hotKeys.isEmpty { stop() }
        return registered
    }

    func stop() {
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
        hotKeys.removeAll(); handler = nil; action = nil
    }
}

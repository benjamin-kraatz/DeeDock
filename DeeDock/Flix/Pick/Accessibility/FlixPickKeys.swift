import Carbon
import CoreGraphics

/// The keystrokes Flix Pick sends to a picker: ⇧⌘G (Go to Folder), Return, and Escape.
///
/// They are posted to the HID event tap with a source in the HID system state, so they reach the
/// frontmost app as if typed; posting to the app's process (`postToPid`) does not open Go to
/// Folder. Because they go to whatever has keyboard focus, the caller checks right before each
/// one that the picker's app is frontmost and the picker has focus (`FlixPickRouter`).
///
/// Never while Secure Event Input is on (a password field anywhere has the keyboard): then
/// ``canType`` is false and the row can only be dragged in. Needs Accessibility permission.
nonisolated enum FlixPickKeys {
    static let goToFolderKey: CGKeyCode = 5 // G
    static let returnKey: CGKeyCode = 36
    static let escapeKey: CGKeyCode = 53

    /// The modifiers that would change a posted key (⌥ would turn ⇧⌘G into ⌥⇧⌘G).
    private static let held: CGEventFlags = [.maskAlternate, .maskCommand, .maskShift, .maskControl]

    static var canType: Bool { !IsSecureEventInputEnabled() }

    /// Whether ⌥, ⌘, ⇧, or ⌃ is down on the keyboard now.
    static var modifiersHeld: Bool {
        !CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty
    }

    /// Waits until the person let go of every modifier (the ⌥ of an ⌥-click), polling every
    /// 20 ms. False when they still hold one after `timeout` or the task was cancelled.
    static func waitForModifiersReleased(timeout: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while modifiersHeld {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return !Task.isCancelled
    }

    /// Posts one key press and release.
    static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}

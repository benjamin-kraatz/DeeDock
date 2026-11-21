import Carbon
import CoreGraphics

/// The one keystroke Flix Pick sends to a picker: ⇧⌘G, which opens Go to Folder and has no
/// Accessibility alternative. Return and Escape are never sent as keys; the Go to Folder sheet is
/// submitted and dismissed through Accessibility actions on its own field or buttons
/// (`FlixPickSession.submitGoToFolder(serial:)`).
///
/// It is posted to the HID event tap with a source in the HID system state, so it reaches the
/// frontmost app as if typed; posting to the app's process (`postToPid`) does not open Go to
/// Folder. Because it goes to whatever has keyboard focus, it is posted from the Accessibility
/// thread right after that thread checked, in the same block, that the picker's app has keyboard
/// focus, the picker is focused, no modifier is held, and Secure Event Input is off
/// (`FlixPickSession.postGoToFolder(serial:generation:)`). Needs Accessibility permission.
nonisolated enum FlixPickKeys {
    static let goToFolderKey: CGKeyCode = 5 // G

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

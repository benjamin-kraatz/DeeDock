import Carbon
import CoreGraphics

/// The keystrokes Flix Pick sends to a picker: ⇧⌘G, which opens Go to Folder and has no
/// Accessibility alternative, and Return, only as the last way to send the Go to Folder sheet on
/// when its field offers no `AXConfirm` and the sheet no default button
/// (`FlixPickSession.submitGoToFolder(_:serial:generation:)`, which also checks that the focused
/// element is still the field holding the path). Escape is never sent; the sheet is dismissed
/// through Accessibility actions on its own field or buttons.
///
/// It is posted to the HID event tap with a source in the HID system state, so it reaches the
/// frontmost app as if typed; posting to the app's process (`postToPid`) does not open Go to
/// Folder. Because it goes to whatever has keyboard focus, it is posted from the Accessibility
/// thread right after that thread checked, in the same block, that the picker's app has keyboard
/// focus, the picker (or its Go to Folder field) is focused, no modifier is held, and Secure Event
/// Input is off (`FlixPickSession.postGoToFolder(serial:generation:)`). Needs Accessibility
/// permission.
nonisolated enum FlixPickKeys {
    static let goToFolderKey: CGKeyCode = 5 // G
    static let returnKey: CGKeyCode = 36

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

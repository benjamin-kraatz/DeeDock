import Carbon

/// One numbered application position on a dock: Control-Option-`label` performs its primary action.
struct QuickLaunchAssignment: Equatable {
    /// One-based position among the dock's visible application icons, from 1 through `QuickLaunchSlots.count`.
    let slot: Int
    let itemID: String

    /// The digit printed on the icon and pressed on the keyboard. Slot 10 uses the 0 key, as on a number row.
    var label: String { QuickLaunchSlots.label(for: slot) }
}

/// Maps a dock's rendered entries to the ten number-row positions.
///
/// Only application icons are numbered, in the order they are drawn from the dock's leading end:
/// pinned apps, then running-only apps. Folders, utility tiles, collapsed-section controls, and
/// drag gaps are skipped, so a number never lands on something whose click is not "open this app".
/// The mapping is recomputed from the current entries whenever the dock changes; nothing is stored.
enum QuickLaunchSlots {
    /// Number-row keys 1 through 9, then 0.
    static let count = 10

    /// Virtual key codes for the number row in slot order. Codes identify physical keys, so the
    /// shortcuts stay on the number row under non-QWERTY layouts.
    static let keyCodes: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0,
    ]

    /// The first `count` application icons in drawing order.
    static func assignments(for entries: [DockRenderSlot]) -> [QuickLaunchAssignment] {
        entries.compactMap(\.item).prefix(count).enumerated().map { index, item in
            QuickLaunchAssignment(slot: index + 1, itemID: item.id)
        }
    }

    /// The item ID for a one-based slot, or nil when the dock has fewer application icons.
    static func itemID(forSlot slot: Int, in entries: [DockRenderSlot]) -> String? {
        assignments(for: entries).first { $0.slot == slot }?.itemID
    }

    /// The one-based slot for a number-row key code, or nil for any other key.
    static func slot(forKeyCode keyCode: UInt16) -> Int? {
        keyCodes.firstIndex(of: Int(keyCode)).map { $0 + 1 }
    }

    /// The digit shown for a one-based slot.
    static func label(for slot: Int) -> String { String(slot % count) }
}

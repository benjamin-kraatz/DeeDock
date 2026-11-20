import AppKit
import Carbon

/// A recordable global key combination: one key plus modifiers, stored as Carbon key code and
/// modifier flags so it survives keyboard layout changes.
nonisolated struct FlixShortcutCombo: Codable, Hashable, Sendable {
    /// The modifiers a combination can hold, in the order macOS draws them.
    nonisolated struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        init(rawValue: UInt8) { self.rawValue = rawValue }

        init(_ flags: NSEvent.ModifierFlags) {
            var value: Modifiers = []
            if flags.contains(.control) { value.insert(.control) }
            if flags.contains(.option) { value.insert(.option) }
            if flags.contains(.shift) { value.insert(.shift) }
            if flags.contains(.command) { value.insert(.command) }
            self = value
        }

        /// "⌃⌥⇧⌘" in Apple's canonical order.
        var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }

        /// The flags `RegisterEventHotKey` takes.
        var carbon: UInt32 {
            var value: UInt32 = 0
            if contains(.control) { value |= UInt32(controlKey) }
            if contains(.option) { value |= UInt32(optionKey) }
            if contains(.shift) { value |= UInt32(shiftKey) }
            if contains(.command) { value |= UInt32(cmdKey) }
            return value
        }
    }

    /// A virtual key code (`kVK_…`).
    var keyCode: UInt16
    var modifiers: Modifiers

    /// Control-Option-Command-F, the default. Never Option-Space, which launchers such as Raycast own.
    static let `default` = FlixShortcutCombo(keyCode: UInt16(kVK_ANSI_F), modifiers: [.control, .option, .command])

    /// Keys that are only modifiers and can never be the key of a combination.
    static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand), UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Option), UInt16(kVK_RightOption), UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock), UInt16(kVK_Function),
    ]

    /// Function keys, which work as a global shortcut without a modifier.
    static let functionKeyCodes: Set<UInt16> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].reduce(into: Set<UInt16>()) { $0.insert(UInt16($1)) }

    /// What a recorder makes of one pressed key.
    nonisolated enum Recording: Equatable, Sendable {
        case combo(FlixShortcutCombo)
        /// A plain key, or one with Shift only, would fire while typing.
        case needsModifier
        /// A modifier on its own: keep listening.
        case incomplete
    }

    /// Interprets a key press in the recorder. A combination needs Control, Option, or Command, except
    /// for function keys, which never type text.
    static func recording(keyCode: UInt16, modifiers: Modifiers) -> Recording {
        if modifierKeyCodes.contains(keyCode) { return .incomplete }
        let combo = FlixShortcutCombo(keyCode: keyCode, modifiers: modifiers)
        if functionKeyCodes.contains(keyCode) { return .combo(combo) }
        guard !modifiers.intersection([.control, .option, .command]).isEmpty else { return .needsModifier }
        return .combo(combo)
    }

    /// "⌃⌥⌘F". Main actor: the Text Input Sources API is not thread-safe.
    @MainActor var displayString: String { modifiers.symbols + Self.keyName(for: keyCode) }

    /// The key's printed name: a fixed name for keys without a character, otherwise the character the
    /// current keyboard layout types for it, uppercased.
    @MainActor static func keyName(for keyCode: UInt16) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        return layoutCharacter(for: keyCode)?.uppercased() ?? ansiNames[keyCode] ?? "#\(keyCode)"
    }

    private static let specialKeyNames: [UInt16: String] = {
        var names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionKeys.enumerated() { names[code] = "F\(index + 1)" }
        return names.reduce(into: [:]) { $0[UInt16($1.key)] = $1.value }
    }()

    /// US names, used when the layout cannot be read.
    private static let ansiNames: [UInt16: String] = {
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"), (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"), (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"),
            (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"), (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_Grave, "`"),
        ]
        return letters.reduce(into: [:]) { $0[UInt16($1.0)] = $1.1 }
    }()

    /// The character the current layout types for `keyCode` without modifiers, via `UCKeyTranslate`.
    @MainActor private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count,
                                        &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: characters, count: length)
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
        }
    }
}

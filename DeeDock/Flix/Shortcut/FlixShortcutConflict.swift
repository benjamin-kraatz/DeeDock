import Carbon
import Foundation

/// Why a recorded combination is a poor choice, known before registering it.
///
/// DOKK's own global shortcuts would silently stop one of the two features working, and a few system
/// combinations are owned by macOS. Another app owning the combination only shows up when
/// registration fails; `FlixShortcut` reports that separately.
nonisolated enum FlixShortcutConflict: Hashable, Sendable {
    /// Radar's Option-Shift-Command-Space or Shift-Command-Space.
    case radar
    /// Robi's Option-Shift-Command-R.
    case robi
    /// Spotlight's Command-Space or Option-Command-Space.
    case spotlight
    /// Command-Tab or Command-Q style combinations every app relies on.
    case system
    /// Option-Space, which launchers such as Raycast use.
    case launcher

    /// The conflict for `combo`, or nil when DOKK knows of none.
    static func conflict(for combo: FlixShortcutCombo) -> FlixShortcutConflict? {
        let space = UInt16(kVK_Space)
        switch (combo.keyCode, combo.modifiers) {
        case (space, [.option, .shift, .command]), (space, [.shift, .command]): return .radar
        case (UInt16(kVK_ANSI_R), [.option, .shift, .command]): return .robi
        case (space, [.command]), (space, [.option, .command]): return .spotlight
        case (space, [.option]): return .launcher
        case (UInt16(kVK_Tab), [.command]), (UInt16(kVK_ANSI_Q), [.command]), (UInt16(kVK_ANSI_W), [.command]),
             (UInt16(kVK_ANSI_H), [.command]), (UInt16(kVK_ANSI_M), [.command]), (UInt16(kVK_ANSI_Grave), [.command]),
             (UInt16(kVK_ANSI_C), [.command]), (UInt16(kVK_ANSI_V), [.command]), (UInt16(kVK_ANSI_X), [.command]),
             (UInt16(kVK_ANSI_Z), [.command]), (UInt16(kVK_ANSI_A), [.command]):
            return .system
        default: return nil
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .radar: .flixShortcutConflictRadar
        case .robi: .flixShortcutConflictRobi
        case .spotlight: .flixShortcutConflictSpotlight
        case .system: .flixShortcutConflictSystem
        case .launcher: .flixShortcutConflictLauncher
        }
    }

    /// Whether the recorder refuses it outright. DOKK's own shortcuts and app-wide commands are
    /// refused; Spotlight and launcher combinations are allowed with a warning, since some people
    /// turned those off.
    var refuses: Bool {
        switch self {
        case .radar, .robi, .system: true
        case .spotlight, .launcher: false
        }
    }
}

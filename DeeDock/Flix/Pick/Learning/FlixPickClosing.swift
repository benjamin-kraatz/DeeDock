import Foundation

/// What Flix Pick saw while a picker was open, for telling how it closed.
struct FlixPickClosingEvidence {
    var kind: FlixPickPickerKind
    /// The list's last selected file (from `kAXSelectedRowsChangedNotification`).
    var selection: URL?
    /// The file or folder Flix Pick last put into the picker. Cleared when the person moved a Save
    /// picker to another folder.
    var placedByFlix: String?
    /// Flix Pick pressed the default button itself, for this path, and the press went through
    /// (a disabled Save button refuses it). Set only from the press's result.
    var confirmedByFlix: (path: String, at: Date)?
    /// The last mouse press on the picker: which control, with its click count.
    var lastPress: (target: FlixPickPressTarget, clickCount: Int, at: Date)?
}

/// Decides how a picker closed, and what was picked, from ``FlixPickClosingEvidence``.
///
/// macOS sends no notification for a button press, and the picker is gone by the time its
/// destruction is reported, so Flix Pick counts only what it can tell for sure:
///
/// - A press on `CancelButton` at most 1.5 seconds before it closed, and after any confirm of Flix
///   Pick's own: cancelled. Cancel wins.
/// - Flix Pick pressed the default button itself (⌥-click, double-click), the press went through,
///   and the picker closed within three seconds: picked, the file or folder Flix Pick put there.
///   A close reported while that press was still running waits for its result
///   (`FlixPickCoordinator`).
/// - A mouse press on `OKButton`, or a double-click in an Open picker's list, at most 1.5 seconds
///   before it closed: picked. An Open picker's choice is the last selected file; a Save picker's
///   is the folder Flix Pick moved it to, when it still showed it (otherwise the folder is unknown
///   and nothing is learned).
/// - Anything else, which includes Return and Escape: unknown, and nothing is learned. Keys are
///   not watched, so a keyboard confirm is missed rather than a cancel ever counted.
///
/// A global mouse-down monitor, which sees only where and how often the button was pressed, runs
/// while a picker is open (`FlixPickCoordinator`).
enum FlixPickClosing {
    static let pressWindow: TimeInterval = 1.5
    static let confirmWindow: TimeInterval = 3

    static func outcome(_ evidence: FlixPickClosingEvidence, closedAt now: Date)
        -> (outcome: AnalyticsFlixPickOutcome, chosen: String?) {
        let recentPress = evidence.lastPress.flatMap { now.timeIntervalSince($0.at) <= pressWindow ? $0 : nil }
        // An explicit Cancel after Flix Pick's own confirm wins: the confirm did not close it.
        if let press = recentPress, press.target == .cancel,
           evidence.confirmedByFlix.map({ press.at >= $0.at }) ?? true {
            return (.cancelled, nil)
        }
        if let confirmed = evidence.confirmedByFlix, now.timeIntervalSince(confirmed.at) <= confirmWindow {
            return (.pickedViaFlixPick, confirmed.path)
        }
        guard let press = recentPress else { return (.unknown, nil) }
        let chosen: String?
        switch press.target {
        case .cancel:
            return (.cancelled, nil)
        case .confirm:
            chosen = evidence.kind == .open ? evidence.selection.map { FlixPaths.standardized($0.path) } : evidence.placedByFlix
        case .list where press.clickCount >= 2 && evidence.kind == .open:
            chosen = evidence.selection.map { FlixPaths.standardized($0.path) }
        case .list, .other:
            return (.unknown, nil)
        }
        guard let chosen else { return (.pickedElsewhere, nil) }
        let placed = evidence.placedByFlix.map(FlixPaths.standardized)
        return (chosen == placed ? .pickedViaFlixPick : .pickedElsewhere, chosen)
    }
}

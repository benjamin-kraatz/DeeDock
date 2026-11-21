#if DEBUG
import Foundation

/// Deterministic sample rows for Flix Pick's previews.
///
/// The paths are in the protected folders of a made-up home folder that the preview read policy
/// refuses, so no file, thumbnail, or permission is touched: rows show the type's real icon from
/// Launch Services (a folder; the Pages document icon where Pages is installed).
@MainActor
enum FlixPickPreviewData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let home = "/Users/mia"

    /// A panel state beside a Pages picker, shown, with no actions wired.
    /// - Parameters:
    ///   - kind: An Open picker lists ``files``, a Save picker ``folders``.
    ///   - open: The open rail or the closed one.
    ///   - rows: How many rows, at most five; zero shows the empty line.
    static func state(kind: FlixPickPickerKind = .open, open: Bool, rows: Int = 5) -> FlixPickState {
        let state = FlixPickState()
        state.kind = kind
        state.appName = "Pages"
        state.buttonTitle = kind == .open ? "Open" : "Save"
        state.rows = Array((kind == .open ? files : folders).prefix(rows))
        state.isOpen = open
        state.isShown = true
        state.now = now
        state.policy = FlixReadPolicy(home: home, allowedRoots: [])
        return state
    }

    private static func row(_ path: String, kind: FlixItemKind, reason: String, tone: FlixPickReason.Tone,
                            location: String, minutes: Double) -> FlixPickRow {
        let date = now.addingTimeInterval(-minutes * 60)
        let item = FlixItem(path: path, name: (path as NSString).lastPathComponent, kind: kind, activity: .opened,
                            date: date, contentTypeIdentifier: kind == .folder ? nil : "com.apple.iwork.pages.sffpages")
        return FlixPickRow(item: item, reason: FlixPickReason(text: reason, tone: tone), location: location, date: date)
    }

    /// One row for each reason colour: context, learned, new, and two used.
    static let files: [FlixPickRow] = [
        row(home + "/Documents/Oak & Ash/Brief v3.pages", kind: .document, reason: "Part of Oak & Ash",
            tone: .context, location: "Documents › Oak & Ash", minutes: 20),
        row(home + "/Documents/Newsletter November.pages", kind: .document, reason: "Picked here 3×",
            tone: .learned, location: "Documents", minutes: 1_440),
        row(home + "/Desktop/Certificate – Mia.pages", kind: .document, reason: "New in Desktop",
            tone: .new, location: "Desktop", minutes: 42),
        row(home + "/Desktop/Client Letters/Quarterly Letter.pages", kind: .document, reason: "Edited recently",
            tone: .used, location: "Desktop › Client Letters", minutes: 180),
        row(home + "/Documents/Offer – Oak & Ash.pages", kind: .document, reason: "You send documents here",
            tone: .used, location: "Documents", minutes: 5_760),
    ]

    static let folders: [FlixPickRow] = [
        row(home + "/Desktop/Client Letters", kind: .folder, reason: "Saved here 3×", tone: .learned,
            location: "Desktop", minutes: 180),
        row(home + "/Documents/Oak & Ash", kind: .folder, reason: "Where your recent Pages files are",
            tone: .used, location: "Documents", minutes: 20),
        row(home + "/Documents/Invoices", kind: .folder, reason: "You saved files here recently", tone: .used,
            location: "Documents", minutes: 2_880),
    ]
}
#endif

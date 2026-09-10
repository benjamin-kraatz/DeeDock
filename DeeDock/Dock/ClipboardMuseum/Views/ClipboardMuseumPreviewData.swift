#if DEBUG
import Foundation

extension ClipboardExhibit {
    /// Deterministic sample collection for previews: prose, a link, a redacted token, a flagged
    /// but unredacted secret, and files. Paths point at system locations that exist on every Mac.
    static let previewCollection: [ClipboardExhibit] = {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        return [
            ClipboardExhibit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, catalogNumber: 42,
                             kind: .text, acquiredAt: now, sourceName: "Notes",
                             text: "The dock should feel familiar before it feels new.\nMatch the look, then the behavior, then the feel.",
                             size: 101),
            ClipboardExhibit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, catalogNumber: 41,
                             kind: .link, acquiredAt: now.addingTimeInterval(-600), sourceName: "Safari",
                             text: "https://developer.apple.com/documentation/appkit/nspasteboard", size: 61),
            ClipboardExhibit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, catalogNumber: 40,
                             kind: .text, acquiredAt: now.addingTimeInterval(-3_600), sourceName: "Terminal",
                             size: 40, redaction: .detected, secret: .accessToken, redactedHint: "ghp_••••"),
            ClipboardExhibit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, catalogNumber: 39,
                             kind: .text, acquiredAt: now.addingTimeInterval(-90_000), sourceName: "TextEdit",
                             text: "password = correct-horse", size: 24, secret: .credential),
            ClipboardExhibit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, catalogNumber: 38,
                             kind: .files, acquiredAt: now.addingTimeInterval(-200_000), sourceName: "Finder",
                             text: "/System/Applications/Notes.app\n/System/Applications/Calendar.app", size: 2),
        ]
    }()
}
#endif

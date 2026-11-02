import SwiftUI

/// What App Health records and how the data is kept, in plain words, beside a neutral lock.
///
/// Once there is data, the note ends with a **Show in Finder** link that opens the records folder. The link uses a
/// private URL that never leaves the view: the local `openURL` action catches it and calls `revealInFinder`.
struct AppHealthPrivacyNote: View {
    /// Whether the records folder exists and holds files, so the link has somewhere to go.
    var showsFinderLink = false
    var revealInFinder: () -> Void = {}

    private static let revealURL = URL(string: "dokk-app-health:reveal")!

    var body: some View {
        SettingsStackedRow {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url == Self.revealURL else { return .systemAction }
                revealInFinder()
                return .handled
            })
        }
    }

    /// The note, and after it the link in the page tint so it reads as the one thing here to click.
    private var note: AttributedString {
        var text = AttributedString(localized: .appHealthPrivacyNote)
        guard showsFinderLink else { return text }
        var link = AttributedString(localized: .appHealthShowInFinder)
        link.link = Self.revealURL
        link.foregroundColor = SettingsPage.appHealth.tint
        text.append(AttributedString(" "))
        text.append(link)
        return text
    }
}

#if DEBUG
#Preview("Privacy note with Finder link") {
    SettingsCard {
        AppHealthPrivacyNote(showsFinderLink: true)
    }
    .frame(width: SettingsMetrics.columnWidth)
    .padding()
}

#Preview("Privacy note, no data, German dark") {
    SettingsCard {
        AppHealthPrivacyNote(showsFinderLink: false)
    }
    .frame(width: SettingsMetrics.columnWidth)
    .padding()
    .environment(\.locale, Locale(identifier: "de"))
    .preferredColorScheme(.dark)
}
#endif

import SwiftUI

/// The apps badge history knows about, as a selectable list rather than a pop-up menu.
///
/// The retained set reaches 100 apps, and each row is worth seeing at a glance: its icon says which
/// app without reading, and the trailing chip is the value the detail pane will explain. A native
/// `List` selection keeps arrow keys and VoiceOver working.
struct BadgeAppList: View {
    let paths: [String]
    let memory: BadgeMemoryStore
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(.badgeMemoryApps)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            List(paths, id: \.self, selection: $selection) { path in
                row(path)
                    .tag(Optional(path))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.badgeMemoryApps))
    }

    private func row(_ path: String) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: BadgeAppArtwork.icon(path))
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(verbatim: badgeAppName(path))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            BadgeValueChip(value: memory.current[path] ?? .unknown)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Tracked apps") {
    @Previewable @State var selection: String? = "/Applications/Mail.app"
    return BadgeAppList(paths: ["/Applications/Mail.app", "/Applications/Messages.app",
                                "/Applications/A removed app.app"],
                        memory: BadgeMemoryStore(defaults: UserDefaults(suiteName: "BadgeListPreview")!),
                        selection: $selection)
        .frame(width: 230, height: 320)
}
#endif

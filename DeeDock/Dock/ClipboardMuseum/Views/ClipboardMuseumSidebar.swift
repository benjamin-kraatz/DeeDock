import SwiftUI

/// The collection list: a wing filter, day galleries of placards, and the collecting status.
///
/// Rename works the Finder way: select a row and press Return, or choose Rename from its context
/// menu. Either opens the title field in the detail placard.
struct ClipboardMuseumSidebar: View {
    let halls: [ClipboardMuseumHall]
    let count: Int
    let captureEnabled: Bool
    @Binding var selection: ClipboardExhibit.ID?
    @Binding var renaming: ClipboardExhibit.ID?
    @Binding var wing: ClipboardMuseumWing
    let actions: ClipboardMuseumActions

    var body: some View {
        List(selection: $selection) {
            ForEach(halls) { hall in
                Section {
                    ForEach(hall.exhibits) { exhibit in
                        ClipboardExhibitRow(exhibit: exhibit)
                            .tag(exhibit.id)
                            .contextMenu { contextMenu(for: exhibit) }
                    }
                } header: {
                    ClipboardMuseumHallTitle(day: hall.day)
                }
            }
        }
        .onDeleteCommand { if let selection { actions.remove(selection) } }
        .onKeyPress(.return) {
            guard let selection, renaming == nil else { return .ignored }
            renaming = selection
            return .handled
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ClipboardMuseumWingPicker(wing: $wing)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(captureEnabled ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(captureEnabled ? .clipboardMuseumCollectingOn : .clipboardMuseumCollectingOff)
                Spacer(minLength: 8)
                Text(.clipboardMuseumExhibitCount(count))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func contextMenu(for exhibit: ClipboardExhibit) -> some View {
        Button { selection = exhibit.id; renaming = exhibit.id } label: { Text(.clipboardMuseumRename) }
        if exhibit.customTitle != nil {
            Button { actions.rename(exhibit.id, nil) } label: { Text(.clipboardMuseumResetName) }
        }
        Button { _ = actions.restore(exhibit, nil) } label: { Text(.clipboardMuseumRestore) }
            .disabled(exhibit.isRedacted)
        Divider()
        if !exhibit.isRedacted {
            Button { actions.redact(exhibit.id) } label: { Text(.clipboardMuseumRedact) }
        }
        Button(role: .destructive) { actions.remove(exhibit.id) } label: { Text(.clipboardMuseumRemove) }
    }
}

/// The wing filter, drawn above the list as a native pop-up menu.
struct ClipboardMuseumWingPicker: View {
    @Binding var wing: ClipboardMuseumWing

    var body: some View {
        Picker(selection: $wing) {
            ForEach(ClipboardMuseumWing.allCases) { Text($0.title).tag($0) }
        } label: {
            Text(.clipboardMuseumWingPicker)
        }
        .pickerStyle(.menu)
    }
}

/// "Today", "Yesterday", or the date, for a day gallery.
private struct ClipboardMuseumHallTitle: View {
    let day: Date

    var body: some View {
        if Calendar.current.isDateInToday(day) {
            Text(.clipboardMuseumHallToday)
        } else if Calendar.current.isDateInYesterday(day) {
            Text(.clipboardMuseumHallYesterday)
        } else {
            Text(day, format: .dateTime.weekday(.wide).month().day())
        }
    }
}

/// A sidebar placard: medium tile, title, catalog number, time, and provenance.
struct ClipboardExhibitRow: View {
    let exhibit: ClipboardExhibit

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: exhibit.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tileColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                exhibit.titleText
                    .lineLimit(1)
                    .italic(exhibit.isRedacted && exhibit.customTitle == nil)
                HStack(spacing: 6) {
                    Text(.clipboardMuseumCatalogNumber(exhibit.catalogNumber))
                        .monospacedDigit()
                    Text(exhibit.acquiredAt, format: .dateTime.hour().minute())
                    if let source = exhibit.sourceName {
                        Text(verbatim: source).lineLimit(1)
                    }
                    if exhibit.curatedTitle != nil, exhibit.customTitle == nil {
                        Image(systemName: "sparkles")
                            .accessibilityLabel(Text(.clipboardMuseumCuratorNote))
                    }
                    if exhibit.secret != nil, !exhibit.isRedacted {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text(.clipboardMuseumConditionSensitive))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var tileColor: Color {
        if exhibit.isRedacted { return Color(white: 0.35) }
        switch exhibit.kind {
        case .text: return Color(red: 0.62, green: 0.46, blue: 0.28)
        case .link: return Color(red: 0.20, green: 0.46, blue: 0.78)
        case .image: return Color(red: 0.56, green: 0.36, blue: 0.70)
        case .files: return Color(red: 0.24, green: 0.56, blue: 0.46)
        }
    }
}

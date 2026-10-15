import SwiftUI

/// Step 2: the folders to read, each with its estimate, "Add folder…", what Lookout never reads, and the first pass
/// in total.
struct LookoutSetupFoldersStep: View {
    let draft: LookoutSetupDraft
    let setChosen: (String, Bool) -> Void
    let addFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LookoutSetupHeading(title: .lookoutSetupFoldersTitle, lead: .lookoutSetupFoldersLead)
            VStack(spacing: 4) {
                ForEach(draft.folders) { folder in
                    LookoutSetupFolderRow(folder: folder, home: draft.home) { setChosen(folder.path, $0) }
                }
            }
            Button(action: addFolder) {
                LookoutAddFolderLabel()
                    .font(.system(size: 12.5))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let notice = draft.addNotice {
                LookoutSetupAddNotice(outcome: notice, home: draft.home)
            }
            LookoutSetupNeverList()
            LookoutSetupTotalLine(total: draft.total)
        }
    }
}

/// One folder with its checkbox, the whole row clickable (the mockup's `.fr`). Unchecked rows fade to 55 %.
private struct LookoutSetupFolderRow: View {
    let folder: LookoutSetupFolder
    let home: String
    let setChosen: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { folder.isChosen }, set: setChosen)) {
            HStack(spacing: 11) {
                LookoutFolderGlyph(size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.displayName)
                        .font(.system(size: 13))
                    Text(verbatim: folder.tildePath(home: home))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LookoutSetupEstimateText(folder: folder)
            }
        }
        .toggleStyle(LookoutSetupCheckboxRowStyle())
    }
}

/// The trailing estimate of a folder row: "412 files" over "about 2 min · 14 MB", or why there's none yet.
private struct LookoutSetupEstimateText: View {
    let folder: LookoutSetupFolder

    var body: some View {
        Group {
            switch folder.estimate {
            case .ready(let estimate):
                VStack(alignment: .trailing, spacing: 1) {
                    Text(.lookoutSetupFiles(estimate.files))
                    Text(verbatim: "\(String(localized: .lookoutSetupAboutMinutes(estimate.minutes))) · "
                        + Int64(estimate.bytes).formatted(.byteCount(style: .file)))
                }
            case .afterAccess:
                Text(.lookoutSetupEstimateAfterAccess)
            case .estimating:
                Text(.lookoutSetupEstimating)
                    .foregroundStyle(.tertiary)
            case .unavailable:
                Text(folder.access == .missing ? .lookoutSetupFolderMissing : .lookoutSetupFolderUnreadable)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .fixedSize()
    }
}

/// Draws a toggle as onboarding's folder row: the 16 pt rounded checkbox, accent when on, then the label; a click
/// anywhere on the row toggles it, and Space does when it has keyboard focus.
private struct LookoutSetupCheckboxRowStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        LookoutSetupCheckboxRow(configuration: configuration)
    }
}

private struct LookoutSetupCheckboxRow: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let isOn = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(isOn ? Color.clear : LookoutTheme(scheme).strongLine, lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .opacity(isOn ? 1 : 0)
                    }
                    .frame(width: 16, height: 16)
                    .animation(HubFilesMotion.animation(.easeOut(duration: 0.15)), value: isOn)
                configuration.label
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .lookoutSetupRow()
        .opacity(isOn ? 1 : 0.55)
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.2)), value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? .lookoutSetupFolderOn : .lookoutSetupFolderOff))
    }
}

/// Why the picked folder wasn't added, under "Add folder…".
private struct LookoutSetupAddNotice: View {
    let outcome: LookoutFolderChoice.Outcome
    let home: String

    var body: some View {
        if let text {
            Label { Text(verbatim: text) } icon: { Image(systemName: "info.circle") }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String? {
        switch outcome {
        case .refused(let refusal): String(localized: refusal.message)
        case .alreadyIncluded(let parent):
            String(localized: .lookoutSetupAlreadyIncluded(LookoutSetupFolder.displayName(of: parent, home: home)))
        case .add: nil
        }
    }
}

/// "Lookout never reads", folded by default (the mockup's `details.never`).
private struct LookoutSetupNeverList: View {
    @State private var isExpanded = false

    private let items: [LocalizedStringResource] = [
        .lookoutSetupNeverLibrary, .lookoutSetupNeverApps, .lookoutSetupNeverSecrets, .lookoutSetupNeverCode,
        .lookoutSetupNeverDatasets, .lookoutSetupNeverCloud,
    ]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded.animation(HubFilesMotion.layout)) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.key) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "•")
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(.lookoutSetupNeverTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// "First pass" and the chosen folders' estimates added up (the mockup's `.tot`).
private struct LookoutSetupTotalLine: View {
    let total: (estimate: LookoutFolderEstimate, pending: Int)

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(.lookoutSetupTotalTitle)
            Spacer(minLength: 12)
            Text(summary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    private var summary: AttributedString {
        let estimate = total.estimate
        guard estimate.files > 0 || total.pending == 0 else {
            return AttributedString(localized: .lookoutSetupEstimateAfterAccess)
        }
        var files = AttributedString(localized: .lookoutSetupFiles(estimate.files))
        files.foregroundColor = .primary
        files.font = .system(size: 12, weight: .semibold)
        var text = files
        text += AttributedString(" · " + String(localized: .lookoutSetupAboutMinutes(estimate.minutes)) + " · "
            + String(localized: .lookoutSetupIndexSize(Int64(estimate.bytes).formatted(.byteCount(style: .file)))))
        if total.pending > 0 {
            text += AttributedString(" · " + String(localized: .lookoutSetupMoreAfterAccess(total.pending)))
        }
        return text
    }
}

extension LookoutFolderChoice.Refusal {
    /// A short explanation for the person.
    var message: LocalizedStringResource {
        switch self {
        case .wholeDisk: .lookoutFolderRefusedDisk
        case .homeFolder: .lookoutFolderRefusedHome
        case .library: .lookoutFolderRefusedLibrary
        case .hidden: .lookoutFolderRefusedHidden
        case .bundle: .lookoutFolderRefusedBundle
        case .system: .lookoutFolderRefusedSystem
        }
    }
}

#Preview("Folders · dark") {
    LookoutSetupSheetPreview(step: .folders)
        .preferredColorScheme(.dark)
}

#Preview("Folders · added, refused, light") {
    LookoutSetupSheetPreview(step: .folders) { draft in
        draft.add("/Users/preview/Projects/Design")
        draft.setEstimate("/Users/preview/Projects/Design", .estimating)
        draft.add("/Users/preview")
    }
    .preferredColorScheme(.light)
}

#Preview("Folders · German") {
    LookoutSetupSheetPreview(step: .folders)
        .environment(\.locale, Locale(identifier: "de"))
}

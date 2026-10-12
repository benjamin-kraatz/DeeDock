import SwiftUI

/// Step 3: each chosen folder, with "Allow…" until macOS has answered, then the answer: Allowed, or "Not allowed ·
/// Skipped" with a way to System Settings. Folders that read without a prompt show Allowed by themselves.
struct LookoutSetupAccessStep: View {
    let draft: LookoutSetupDraft
    let requestAccess: (String) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LookoutSetupHeading(title: .lookoutSetupAccessTitle, lead: .lookoutSetupAccessLead)
            VStack(spacing: 6) {
                ForEach(draft.chosen) { folder in
                    LookoutSetupAccessRow(folder: folder, requestAccess: { requestAccess(folder.path) },
                                          openSettings: openSettings)
                }
            }
        }
    }
}

/// One folder and where its access stands (the mockup's `.acc`).
private struct LookoutSetupAccessRow: View {
    let folder: LookoutSetupFolder
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            LookoutFolderGlyph(size: 22)
            Text(folder.displayName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            LookoutSetupAccessState(access: folder.access, requestAccess: requestAccess, openSettings: openSettings)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .lookoutSetupRow()
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.2)), value: folder.access)
        .accessibilityElement(children: .contain)
    }
}

private struct LookoutSetupAccessState: View {
    let access: LookoutFolderAccess
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        switch access {
        case .unknown:
            Button(.lookoutSetupAllow, action: requestAccess)
                .buttonStyle(.lookoutMini)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(Text(.lookoutSetupAccessChecking))
        case .allowed:
            Label { Text(.lookoutSetupAllowed) } icon: { Image(systemName: "checkmark").fontWeight(.bold) }
                .labelStyle(LookoutSetupStatusLabelStyle())
                .foregroundStyle(LookoutTheme.ready)
        case .denied:
            HStack(spacing: 10) {
                Text(.lookoutSetupDeniedSkipped)
                    .font(.system(size: 12))
                    .foregroundStyle(LookoutTheme.paused)
                Button(.lookoutSetupOpenSettings, action: openSettings)
                    .buttonStyle(.lookoutMini)
            }
        case .missing:
            Text(.lookoutSetupMissingSkipped)
                .font(.system(size: 12))
                .foregroundStyle(LookoutTheme.paused)
        }
    }
}

/// A 13 pt icon beside 12 pt text, 6 pt apart (the mockup's `.st`).
private struct LookoutSetupStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11))
            configuration.title.font(.system(size: 12))
        }
    }
}

#Preview("Access · each answer") {
    LookoutSetupSheetPreview(step: .access) { draft in
        draft.setAccess("/Users/preview/Desktop", .allowed)
        draft.setAccess("/Users/preview/Documents", .denied)
        draft.add("/Volumes/Archive/Scans")
        draft.setAccess("/Volumes/Archive/Scans", .checking)
    }
    .preferredColorScheme(.dark)
}

#Preview("Access · not asked, light, German") {
    LookoutSetupSheetPreview(step: .access)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "de"))
}

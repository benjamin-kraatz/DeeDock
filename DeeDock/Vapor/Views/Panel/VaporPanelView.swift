import SwiftUI

/// The panel that opens beside the orb: header, Finder suggestions, folder rows, drop zone and
/// the hold-to-delete footer. Hosted in a non-activating panel by ``VaporPanelWindowController``,
/// which sizes the window to this view's fitting size and handles drops on it.
struct VaporPanelView: View {
    let controller: VaporController

    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VaporPanelHeader(controller: controller)
            if controller.offersFinderAccess {
                VaporFinderAccessRow { controller.requestFinderAccess?() }
            }
            if !controller.suggestions.isEmpty {
                VaporFoundInSection(folderName: controller.finderFolder?.lastPathComponent ?? "",
                                    suggestions: controller.suggestions,
                                    add: controller.addSuggestion, addAll: controller.addAllSuggestions)
            }
            if controller.folders.isEmpty {
                VaporPanelEmptyState()
            } else {
                VaporFolderList(folders: controller.folders, home: controller.home, remove: controller.remove)
            }
            VaporDropZone(isTargeted: controller.dropHover.isOverPanel)
            if !controller.folders.isEmpty {
                VaporPanelFooter(controller: controller)
            }
        }
        .frame(width: Self.width)
        .vaporGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                    reduceTransparency: controller.reduceTransparency)
    }
}

/// Mini orb, "Vapor", the summary, and Clear.
private struct VaporPanelHeader: View {
    let controller: VaporController

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.clear)
                .vaporGlass(in: Circle(), reduceTransparency: controller.reduceTransparency)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(.vaporTitle)
                    .font(.headline)
                Text(verbatim: VaporCopy.summary(controller.totals))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Button(.vaporClear) { controller.clear() }
                .buttonStyle(.borderless)
                .disabled(controller.folders.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// "Show caches from the open Finder folder · Turn On", while Automation isn't decided.
private struct VaporFinderAccessRow: View {
    let turnOn: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(.vaporFinderAccessPrompt)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(.vaporTurnOn, action: turnOn)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// "Drop build folders and caches here." for an empty orb.
private struct VaporPanelEmptyState: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(.vaporEmptyTitle)
                .font(.callout.weight(.medium))
            Text(.vaporEmptyDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

/// "Drop more folders here", highlighted while a drag hovers the panel.
private struct VaporDropZone: View {
    let isTargeted: Bool

    var body: some View {
        Text(.vaporDropMore)
            .font(.caption)
            .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                    .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear,
                                in: .rect(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

/// Total, the hold button and the note under it.
private struct VaporPanelFooter: View {
    let controller: VaporController

    var body: some View {
        let totals = controller.totals
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: VaporCopy.total(totals))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            VaporHoldButton(controller: controller)
            VaporFooterNote(unknownCount: controller.unknownCount)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }
}

/// "Skips the Trash…", or the unknown-folder warning when one applies.
private struct VaporFooterNote: View {
    let unknownCount: Int

    var body: some View {
        Group {
            if unknownCount > 0 {
                Text(.vaporUnknownNote(unknownCount))
                    .foregroundStyle(.orange)
            } else {
                Text(.vaporSkipsTrashNote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Empty, Finder access undecided") {
    VaporPanelView(controller: VaporPreviewData.controller(panel: true, permission: .undetermined))
        .padding()
}

#Preview("Calculating") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.calculating, panel: true))
        .padding()
}

#Preview("Mixed known and unknown") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true))
        .padding()
}

#Preview("Found in Finder folder") {
    VaporPanelView(controller: VaporPreviewData.controller(Array(VaporPreviewData.mixed.prefix(1)), panel: true,
                                                           suggestions: Array(VaporPreviewData.suggestions.prefix(3))))
        .padding()
}

#Preview("Failure") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.failed, panel: true))
        .padding()
}

#Preview("Reduce Transparency, dark") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true, reduceTransparency: true))
        .padding()
        .preferredColorScheme(.dark)
}
#endif

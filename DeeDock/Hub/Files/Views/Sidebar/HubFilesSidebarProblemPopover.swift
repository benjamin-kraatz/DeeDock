import SwiftUI

/// Explains why an added folder doesn't open: it can't be found (offer to remove it), or it lives
/// on a drive that isn't connected (it comes back by itself).
///
/// Laid out as in the mockup: the warning glyph in its own column, the title and the explanation
/// aligned beside it, the buttons right-aligned underneath. Holds an anchored Hub open while it
/// shows, because a popover takes key focus and the Hub would otherwise close on losing it.
struct HubFilesSidebarProblemPopover: View {
    let model: HubFilesModel
    let entryID: HubFilesSidebarEntryID
    let title: String
    let status: HubFilesSidebarResolution.Status

    @State private var holdingShell: HubShell?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: status == .missing ? "exclamationmark.triangle.fill" : "externaldrive.badge.xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status == .missing ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if status == .missing {
                    Button(.hubFilesSidebarRemove) {
                        model.sidebar.problem = nil
                        model.sidebar.remove(entryID, method: .popover)
                    }
                }
                Button(.hubFilesAlertOK) { model.sidebar.problem = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            guard holdingShell == nil, let shell = model.shell else { return }
            holdingShell = shell
            shell.beginHold(.modal)
        }
        .onDisappear {
            holdingShell?.endHold(.modal)
            holdingShell = nil
        }
    }

    private var headline: LocalizedStringResource {
        switch status {
        case .disconnected(let volume): .hubFilesSidebarDisconnectedTitle(volume)
        default: .hubFilesSidebarMissingTitle(title)
        }
    }

    private var message: LocalizedStringResource {
        switch status {
        case .disconnected(let volume): .hubFilesSidebarDisconnectedMessage(volume, title)
        default: .hubFilesSidebarMissingMessage
        }
    }
}

#Preview("Problem popover · missing") {
    HubFilesSidebarProblemPopover(model: .preview(), entryID: .folder(UUID()), title: "kuki", status: .missing)
}

#Preview("Problem popover · disconnected") {
    HubFilesSidebarProblemPopover(model: .preview(), entryID: .folder(UUID()), title: "Footage",
                                  status: .disconnected(volume: "Transfair"))
}

#Preview("Problem popover · German, light") {
    HubFilesSidebarProblemPopover(model: .preview(), entryID: .folder(UUID()), title: "Steuerunterlagen 2025",
                                  status: .missing)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.light)
}

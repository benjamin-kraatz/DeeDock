import SwiftUI

/// One leftover in the uninstall sheet: a native checkbox (or a lock, or its removal progress), the kind's
/// icon and title, the path, a note, and the size.
///
/// The whole row is the checkbox's label, so clicking anywhere on it toggles the item and VoiceOver reads
/// it as one checkbox.
struct HubUninstallItemRow: View {
    let session: AppUninstallSession
    let item: AppLeftover

    var body: some View {
        if let progress = session.itemProgress[item.id] {
            HStack(spacing: 8) {
                HubUninstallProgressMark(progress: progress)
                label
            }
            .opacity(progress == .failed ? 0.6 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(progress == .failed ? .hubUninstallNotMoved : .hubUninstallMoved))
        } else if item.isProtected {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                    .accessibilityLabel(Text(.hubUninstallProtected))
                label.opacity(0.55)
            }
            .accessibilityElement(children: .combine)
        } else {
            Toggle(isOn: Binding(get: { session.isSelected(item) }, set: { session.setSelected($0, item) })) { label }
                .toggleStyle(.checkbox)
                .disabled(!session.isEditable)
                // Unselected rows fade while the selection is removed, like the mockup's skipped rows.
                .opacity(session.phase.isWorking && !session.isSelected(item) ? 0.38 : 1)
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            HubUninstallKindIcon(kind: item.kind)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.kind.title).font(.system(size: 13))
                    if item.match == .similarName {
                        Text(.hubUninstallNameMatch)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.07)))
                    }
                }
                Text(verbatim: AppUninstallFormat.path(item.url))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note {
                    note.font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Group {
                if item.isProtected { Text(.hubUninstallNotChecked) } else { AppUninstallFormat.size(session.measures[item.id]) }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .contentShape(.rect)
        .help(item.url.path)
    }

    private var note: Text? {
        if let other = item.sharedWith { return Text(.hubUninstallSharedWith(name: other)) }
        switch (item.domain == .allUsers, item.keepsRunning) {
        case (true, true): return Text("\(Text(.hubUninstallAllUsers)) · \(Text(.hubUninstallKeepsRunning))")
        case (true, false): return Text(.hubUninstallAllUsers)
        case (false, true): return Text(.hubUninstallKeepsRunning)
        case (false, false): return nil
        }
    }
}

/// The app bundle's row: always included, so its checkbox is checked and disabled.
struct HubUninstallAppRow: View {
    let session: AppUninstallSession

    var body: some View {
        HStack(spacing: 8) {
            if let progress = session.appProgress {
                HubUninstallProgressMark(progress: progress)
            } else {
                Toggle(isOn: .constant(true)) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(true)
                    .frame(width: 18)
            }
            HStack(spacing: 10) {
                HubUninstallAppIcon(url: session.appURL, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.appURL.lastPathComponent).font(.system(size: 13))
                    Text(verbatim: AppUninstallFormat.path(session.appURL.deletingLastPathComponent()))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                AppUninstallFormat.size(session.appSize)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .frame(minHeight: 42)
        .accessibilityElement(children: .combine)
    }
}

/// A removal mark: a spinner while the item moves, a green check once it's in the Trash, a red cross if
/// it stayed. The check pops in on the Hub's spring.
struct HubUninstallProgressMark: View {
    let progress: AppUninstallSession.ItemProgress

    var body: some View {
        Group {
            switch progress {
            case .working:
                ProgressView().controlSize(.small)
            case .moved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .font(.system(size: 15))
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// The rounded tile with the kind's symbol.
struct HubUninstallKindIcon: View {
    let kind: AppLeftover.Kind

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
            .accessibilityHidden(true)
    }
}

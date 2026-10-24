import SwiftUI

/// One leftover in the uninstall sheet: a native checkbox (or a lock, or its removal progress), the kind's
/// icon and title, the path, a note, and the size.
///
/// The whole row is the checkbox's label, so clicking anywhere on it toggles the item and VoiceOver reads
/// it as one checkbox. While removal runs, rows that won't move fade to 38 % (mockup `.row.skip`).
struct HubUninstallItemRow: View {
    let session: AppUninstallSession
    let item: AppLeftover

    var body: some View {
        let working = session.phase.isWorking
        Group {
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
                    // Locked text sits at 50 % (mockup `.row.locked`); during removal the whole row takes
                    // the skipped rows' 38 % instead, so the two fades don't stack.
                    label.opacity(working ? 1 : 0.5)
                }
                .opacity(working ? 0.38 : 1)
                .accessibilityElement(children: .combine)
            } else {
                Toggle(isOn: Binding(get: { session.isSelected(item) }, set: { session.setSelected($0, item) })) { label }
                    .toggleStyle(.checkbox)
                    .disabled(!session.isEditable)
                    .opacity(working && !session.isSelected(item) ? 0.38 : 1)
            }
        }
        .hubUninstallRow(hoverable: session.isEditable)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            HubUninstallSizeCell {
                if item.isProtected { Text(.hubUninstallNotChecked) } else { AppUninstallFormat.size(session.measures[item.id]) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                HubUninstallSizeCell { AppUninstallFormat.size(session.appSize) }
            }
        }
        .hubUninstallRow(hoverable: false)
        .accessibilityElement(children: .combine)
    }
}

/// The right-aligned size column (mockup `.sz`): 12 pt, tabular digits, at least 62 pt so sizes line up.
private struct HubUninstallSizeCell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(minWidth: 62, alignment: .trailing)
    }
}

/// A removal mark: a spinner while the item moves, a green check once it's in the Trash, a red cross if
/// it stayed.
///
/// The check lands with a small bounce (mockup `pop`: 0.35 s, `cubic-bezier(.3,1.7,.5,1)`), timed by its
/// own spring rather than the sheet's. Reduce Motion fades it in.
struct HubUninstallProgressMark: View {
    let progress: AppUninstallSession.ItemProgress

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let pop = Animation.spring(response: 0.36, dampingFraction: 0.55)

    var body: some View {
        Group {
            switch progress {
            case .working:
                ProgressView().controlSize(.small)
            case .moved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity).animation(Self.pop))
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 15))
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// The rounded tile with the kind's symbol (mockup `.ki`: 26 pt, radius 7).
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

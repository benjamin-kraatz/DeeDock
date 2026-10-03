import SwiftUI

/// The resting card: Open in Finder, Eject, and whether anything is using the volume.
///
/// Fixed external disks get a compact red eject icon instead of a full-width button, because
/// ejecting them cuts off apps and backups that expect the disk to stay connected.
struct VolumeCardInfoSection: View {
    let kind: VolumeKind
    let usage: VolumeCardUsage
    let reduceMotion: Bool
    let perform: (VolumeCardAction) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { perform(.openInFinder) } label: {
                    Text(.volumeOpenInFinder).frame(maxWidth: .infinity)
                }
                if kind == .externalDisk {
                    Button { perform(.eject) } label: {
                        Label { Text(.volumeEject) } icon: {
                            Image(systemName: "eject.fill").foregroundStyle(.red)
                        }
                        .labelStyle(.iconOnly)
                        .padding(.horizontal, 6)
                    }
                    .help(Text(.volumeEject))
                } else {
                    Button { perform(.eject) } label: {
                        Label { Text(.volumeEject) } icon: { Image(systemName: "eject.fill") }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Divider()
            VolumeCardUsageRow(usage: usage, reduceMotion: reduceMotion)
        }
    }
}

/// A status dot and one line saying whether files on the volume are open.
struct VolumeCardUsageRow: View {
    let usage: VolumeCardUsage
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 8) {
            indicator.frame(width: 10, height: 10)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: usage)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var indicator: some View {
        switch usage {
        case .checking: ProgressView().controlSize(.mini)
        case .idle: Circle().fill(.green)
        case .inUse: Circle().fill(.orange)
        }
    }

    private var text: LocalizedStringResource {
        switch usage {
        case .checking: .volumeUsageChecking
        case .idle: .volumeUsageIdle
        case .inUse(let blockers): .volumeUsageInUse(names: VolumeBlockerNames.list(blockers))
        }
    }
}

/// Joins blocker names the way the current language lists things ("Preview and Terminal").
enum VolumeBlockerNames {
    static func list(_ blockers: [VolumeBlocker]) -> String {
        ListFormatter.localizedString(byJoining: blockers.map(\.name))
    }
}

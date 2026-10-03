import AppKit
import SwiftUI

/// Explains a refused eject and offers what can resolve it: show or quit the app holding files
/// open, try again, or eject anyway.
struct VolumeCardBlockedSection: View {
    /// Empty when macOS refused without naming a process DOKK can see.
    let blockers: [VolumeBlocker]
    /// Set for a failure other than open files; replaces the explanation with macOS's message.
    var failure: String? = nil
    let quitting: Set<pid_t>
    let perform: (VolumeCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(.volumeEjectFailedTitle).font(.headline) } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !blockers.isEmpty {
                VStack(spacing: 6) {
                    ForEach(blockers) { blocker in
                        VolumeBlockerRow(blocker: blocker, quitting: quitting.contains(blocker.pid), perform: perform)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { perform(.retry) } label: { Text(.volumeRetry).frame(maxWidth: .infinity) }
                Button(role: .destructive) { perform(.forceEject) } label: {
                    Text(.volumeForceEject).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var message: LocalizedStringResource {
        if let failure { return .volumeEjectFailedDetails(details: failure) }
        let applications = blockers.filter(\.isApplication)
        if blockers.count == 1, let only = applications.first { return .volumeBlockedOneApp(app: only.name) }
        if blockers.count == 1 { return .volumeBlockedOneProcess }
        return blockers.isEmpty ? .volumeBlockedUnknown : .volumeBlockedMany
    }
}

/// One process holding files open, with Show and Quit when it is an application.
struct VolumeBlockerRow: View {
    let blocker: VolumeBlocker
    let quitting: Bool
    let perform: (VolumeCardAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: blocker.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if blocker.isSystem {
                    Text(.volumeBlockerSystemProcess).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if quitting {
                ProgressView().controlSize(.small)
                Text(.volumeBlockerQuitting).font(.caption).foregroundStyle(.secondary)
            } else if blocker.isApplication {
                Button { perform(.showApplication(blocker.pid)) } label: { Text(.volumeBlockerShow) }
                Button { perform(.quitApplication(blocker.pid)) } label: { Text(.volumeBlockerQuit) }
            } else if let path = blocker.executablePath {
                Button { perform(.revealExecutable(path)) } label: { Text(.volumeBlockerReveal) }
                    .help(Text(verbatim: path))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        if blocker.isApplication, let image = NSRunningApplication(processIdentifier: blocker.pid)?.icon {
            Image(nsImage: image).resizable().accessibilityHidden(true)
        } else {
            Image(systemName: blocker.isSystem ? "gearshape.2" : "terminal")
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

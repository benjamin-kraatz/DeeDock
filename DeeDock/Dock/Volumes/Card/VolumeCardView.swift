import SwiftUI

/// The card a volume tile shows on hover, and the place every eject reports its outcome.
struct VolumeCardView: View {
    @Bindable var state: VolumeCardState
    static let width: CGFloat = 340

    var body: some View {
        content
            .padding(16)
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.heightChanged?($0) }
            .dockPopoverChrome(state.chrome, opaque: state.reduceTransparency)
            .onHover { state.hovered?($0) }
            .animation(phaseAnimation, value: state.phase)
    }

    @ViewBuilder private var content: some View {
        if state.phase == .ejected {
            VolumeCardFarewell(name: state.volume.name, reduceMotion: state.reduceMotion)
                .transition(phaseTransition)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VolumeCardHeader(volume: state.volume, reduceMotion: state.reduceMotion,
                                 dimmed: state.phase == .ejecting)
                section
                    .id(sectionID)
                    .transition(phaseTransition)
            }
        }
    }

    @ViewBuilder private var section: some View {
        let perform: (VolumeCardAction) -> Void = { action in state.perform?(action) }
        switch state.phase {
        case .info:
            VolumeCardInfoSection(kind: state.volume.kind, usage: state.usage,
                                  reduceMotion: state.reduceMotion, perform: perform)
        case .confirmDisk:
            VolumeCardConfirmation(symbol: "externaldrive.fill.badge.exclamationmark",
                                   title: .volumeConfirmDiskTitle(name: state.volume.name),
                                   message: .volumeConfirmDiskMessage, confirmTitle: .volumeEject,
                                   confirm: .confirmEject, perform: perform)
        case .ejecting:
            VolumeCardEjectingSection()
        case .blocked(let blockers):
            VolumeCardBlockedSection(blockers: blockers, quitting: state.quitting, perform: perform)
        case .confirmForce:
            VolumeCardConfirmation(symbol: "exclamationmark.triangle.fill", title: .volumeConfirmForceTitle,
                                   message: .volumeConfirmForceMessage, confirmTitle: .volumeForceEject,
                                   confirm: .confirmForceEject, perform: perform)
        case .failed(let details):
            VolumeCardBlockedSection(blockers: [], failure: details, quitting: [], perform: perform)
        case .ejected:
            EmptyView()
        }
    }

    /// Phases change identity so their content cross-fades instead of morphing in place. Blocked
    /// lists keep one identity while their rows update.
    private var sectionID: String {
        switch state.phase {
        case .info: "info"
        case .confirmDisk: "confirmDisk"
        case .ejecting: "ejecting"
        case .blocked: "blocked"
        case .confirmForce: "confirmForce"
        case .failed: "failed"
        case .ejected: "ejected"
        }
    }

    private var phaseAnimation: Animation {
        state.reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.18)
    }

    private var phaseTransition: AnyTransition {
        state.reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                                     .combined(with: .offset(y: 6)),
                          removal: .opacity)
    }
}

#if DEBUG
@MainActor
private enum VolumeCardPreviewData {
    static func volume(name: String = "USB-Stick", kind: VolumeKind = .removable,
                       total: Int64? = 128_000_000_000, available: Int64? = 42_000_000_000,
                       ejecting: Bool = false) -> VolumeDockItem {
        let icon = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil) ?? NSImage()
        return VolumeDockItem(info: VolumeInfo(volumeID: "preview-\(name)", url: URL(fileURLWithPath: "/Volumes/\(name)"),
                                               name: name, kind: kind, totalCapacity: total, availableCapacity: available),
                              icon: icon, isEjecting: ejecting)
    }

    static func state(_ phase: VolumeCardPhase, usage: VolumeCardUsage = .idle,
                      volume: VolumeDockItem? = nil, reduceMotion: Bool = false) -> VolumeCardState {
        let state = VolumeCardState(volume: volume ?? Self.volume(), phase: phase,
                                    chrome: DockPopoverChrome(edge: .bottom, attachment: VolumeCardView.width / 2),
                                    reduceMotion: reduceMotion, reduceTransparency: false)
        state.usage = usage
        return state
    }

    static let preview = VolumeBlocker(pid: 101, name: "Preview", isApplication: true)
    static let terminal = VolumeBlocker(pid: 102, name: "Terminal", isApplication: true)
    static let shell = VolumeBlocker(pid: 103, name: "rsync", isApplication: false, executablePath: "/usr/bin/rsync")
    static let daemon = VolumeBlocker(pid: 104, name: "revisiond", isApplication: false,
                                      executablePath: "/System/Library/PrivateFrameworks/GenerationalStorage.framework/Versions/A/Support/revisiond",
                                      isSystem: true)
}

#Preview("Info, not in use") {
    VolumeCardView(state: VolumeCardPreviewData.state(.info)).padding()
}

#Preview("Info, checking") {
    VolumeCardView(state: VolumeCardPreviewData.state(.info, usage: .checking)).padding()
}

#Preview("Info, nearly full and in use") {
    VolumeCardView(state: VolumeCardPreviewData.state(
        .info, usage: .inUse([VolumeCardPreviewData.preview, VolumeCardPreviewData.terminal]),
        volume: VolumeCardPreviewData.volume(name: "Fotos 2026 – Sicherung mit sehr langem Namen",
                                             kind: .externalDisk, total: 2_000_000_000_000,
                                             available: 60_000_000_000))).padding()
}

#Preview("Info, hard disk") {
    VolumeCardView(state: VolumeCardPreviewData.state(
        .info, volume: VolumeCardPreviewData.volume(name: "WDElements", kind: .externalDisk,
                                                    total: 3_000_000_000_000, available: 2_260_000_000_000))).padding()
}

#Preview("Info, capacity unknown") {
    VolumeCardView(state: VolumeCardPreviewData.state(
        .info, volume: VolumeCardPreviewData.volume(name: "Server", kind: .network, total: nil, available: nil))).padding()
}

#Preview("Confirm hard disk") {
    VolumeCardView(state: VolumeCardPreviewData.state(
        .confirmDisk, volume: VolumeCardPreviewData.volume(name: "Backup", kind: .externalDisk))).padding()
}

#Preview("Ejecting") {
    VolumeCardView(state: VolumeCardPreviewData.state(.ejecting, volume: VolumeCardPreviewData.volume(ejecting: true)))
        .padding()
}

#Preview("Blocked by one app") {
    VolumeCardView(state: VolumeCardPreviewData.state(.blocked([VolumeCardPreviewData.preview]))).padding()
}

#Preview("Blocked by several, one quitting") {
    let state = VolumeCardPreviewData.state(.blocked([VolumeCardPreviewData.preview, VolumeCardPreviewData.terminal,
                                                      VolumeCardPreviewData.shell]))
    state.quitting = [VolumeCardPreviewData.terminal.pid]
    return VolumeCardView(state: state).padding()
}

#Preview("Blocked by a system process") {
    VolumeCardView(state: VolumeCardPreviewData.state(.blocked([VolumeCardPreviewData.daemon]))).padding()
}

#Preview("Blocked, nothing named") {
    VolumeCardView(state: VolumeCardPreviewData.state(.blocked([]))).padding()
}

#Preview("Confirm force eject") {
    VolumeCardView(state: VolumeCardPreviewData.state(.confirmForce([VolumeCardPreviewData.preview]))).padding()
}

#Preview("Failed") {
    VolumeCardView(state: VolumeCardPreviewData.state(.failed("The operation couldn’t be completed. (Disk Arbitration error -119930872.)")))
        .padding()
}

#Preview("Safe to remove") {
    VolumeCardView(state: VolumeCardPreviewData.state(.ejected)).padding()
}

#Preview("Safe to remove, Reduce Motion") {
    VolumeCardView(state: VolumeCardPreviewData.state(.ejected, reduceMotion: true)).padding()
}

#Preview("Info, dark") {
    VolumeCardView(state: VolumeCardPreviewData.state(.info)).padding().preferredColorScheme(.dark)
}
#endif

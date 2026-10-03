import AppKit
import Observation

/// What the volume card shows below its header.
enum VolumeCardPhase: Equatable {
    /// Capacity, Open and Eject, and whether anything is using the volume.
    case info
    /// Asks before ejecting a fixed external disk, when Settings requires it.
    case confirmDisk
    case ejecting
    /// macOS refused the eject. The list names what DOKK could identify and may be empty.
    case blocked([VolumeBlocker])
    /// Asks before forcing an eject past open files.
    case confirmForce([VolumeBlocker])
    case failed(String)
    /// The farewell: the device can be unplugged. The card closes on its own shortly after.
    case ejected

    /// Sticky phases hold the card open after the pointer leaves, until an outside click,
    /// Escape, or the phase resolves. Only the plain info card follows hover.
    var isSticky: Bool { self != .info }
}

/// Whether anything currently holds files open on the volume, as checked when the card opened.
enum VolumeCardUsage: Equatable {
    case checking
    case idle
    case inUse([VolumeBlocker])
}

/// Every button the card offers. The coordinator decides what each one does.
enum VolumeCardAction: Equatable {
    case openInFinder
    case eject
    case confirmEject
    case forceEject
    case confirmForceEject
    case retry
    case cancel
    case showApplication(pid_t)
    case quitApplication(pid_t)
    case dismiss
}

/// Observable model for one volume card presentation.
@MainActor @Observable
final class VolumeCardState {
    var volume: VolumeDockItem
    var phase: VolumeCardPhase
    var usage: VolumeCardUsage = .checking
    var chrome: DockPopoverChrome
    /// Applications the user asked to quit from this card; their rows show progress.
    var quitting: Set<pid_t> = []
    /// Captured once per presentation. Reduce Motion swaps springs and slides for fades.
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @ObservationIgnored var perform: ((VolumeCardAction) -> Void)?
    @ObservationIgnored var hovered: ((Bool) -> Void)?
    /// Reports the content's natural height so the panel can size itself to it.
    @ObservationIgnored var heightChanged: ((CGFloat) -> Void)?

    init(volume: VolumeDockItem, phase: VolumeCardPhase, chrome: DockPopoverChrome,
         reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
         reduceTransparency: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) {
        self.volume = volume
        self.phase = phase
        self.chrome = chrome
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }
}

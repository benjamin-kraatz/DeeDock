import SwiftUI
import Observation

/// Cancellable per-dock tooltip timing. Requests are identity-based, never pointer-frame based.
@MainActor @Observable
final class DockTooltipController {
    struct Request: Equatable {
        let target: DockEntryID?
        let preset: DockTooltipPreset
        var keyboard = false
        var reduceMotion = false
    }
    /// The label on screen and where it sits, kept so Window Peek can take it over.
    struct Presented {
        let target: DockEntryID
        /// The artwork's frame in the dock's root space (`dockRoot`), top-left origin.
        let frame: CGRect
        let artwork: DockTooltipArtwork
    }

    private(set) var revision = 0
    private(set) var visible: DockEntryID?
    /// Written by the overlay as the visible label lays out. Unobserved, because nothing redraws
    /// from it; only read when a Window Peek opens over the labelled tile.
    @ObservationIgnored var presented: Presented?
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var pending: DockScheduledAction?
    @ObservationIgnored private var generation = UUID()
    /// False for the Settings preview, so playing a preview never counts as a tooltip shown.
    @ObservationIgnored private let countsReveals: Bool

    /// - Parameter countsReveals: Whether reveals feed the `tooltip_shown_*` counters. Only the
    ///   dock's own controller does; previews pass false.
    init(scheduler: (any DockVisibilityScheduling)? = nil, countsReveals: Bool = true) {
        self.scheduler = scheduler ?? DockVisibilityScheduler()
        self.countsReveals = countsReveals
    }

    func update(_ next: Request) {
        guard next != request else { return }
        cancel(); request = next
        guard let target = next.target, next.preset != .off else { visible = nil; return }
        // Only dock captions preserve the old label during a new target's delay.
        if next.preset.placement != .dockCenter { visible = nil }
        let counts = countsReveals
        let reveal = { [weak self] in
            if counts, self?.visible != target { Analytics.count(.tooltipShown(keyboard: next.keyboard)) }
            withAnimation(next.preset.animation(reduceMotion: next.reduceMotion)) { self?.visible = target }
        }
        if next.keyboard || next.preset.delay == 0 { reveal(); return }
        let token = generation
        pending = scheduler.schedule(after: next.preset.delay) { [weak self] in
            guard let self, generation == token else { return }
            pending = nil; reveal()
        }
    }

    /// Used for invalidated content, menus, hiding, and sleep. A subsequent request starts a fresh delay.
    func clear() { cancel(); request = nil; visible = nil; presented = nil; revision &+= 1 }
    private func cancel() { generation = UUID(); pending?.cancel(); pending = nil }
}

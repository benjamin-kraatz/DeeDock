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
    private(set) var revision = 0
    private(set) var visible: DockEntryID?
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var pending: DockScheduledAction?
    @ObservationIgnored private var generation = UUID()

    init(scheduler: (any DockVisibilityScheduling)? = nil) {
        self.scheduler = scheduler ?? DockVisibilityScheduler()
    }

    func update(_ next: Request) {
        guard next != request else { return }
        cancel(); request = next
        guard let target = next.target, next.preset != .off else { visible = nil; return }
        // Only dock captions preserve the old label during a new target's delay.
        if next.preset.placement != .dockCenter { visible = nil }
        let reveal = { [weak self] in
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
    func clear() { cancel(); request = nil; visible = nil; revision &+= 1 }
    private func cancel() { generation = UUID(); pending?.cancel(); pending = nil }
}

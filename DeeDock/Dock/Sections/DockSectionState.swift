import Foundation
import Observation

/// Session-local expansion, with a cancellable drag dwell. No state is written to preferences.
@MainActor @Observable
final class DockSectionState {
    private(set) var visibility: DockAppVisibility = .showAll
    private(set) var expanded = false
    private(set) var dragExpanded = false
    var isExpanded: Bool { expanded || dragExpanded }
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var pending: DockScheduledAction?
    @ObservationIgnored private var generation = UUID()

    init(scheduler: (any DockVisibilityScheduling)? = nil) {
        self.scheduler = scheduler ?? DockVisibilityScheduler()
    }

    func configure(_ value: DockAppVisibility) {
        guard value != visibility else { return }
        cancelDwell()
        visibility = value; expanded = false; dragExpanded = false
        didChange?()
    }

    func toggle() {
        guard visibility.collapsedGroup != nil else { return }
        cancelDwell()
        expanded.toggle()
        didChange?()
    }

    /// Leaving cancels only a pending dwell; an opened drag destination stays open until completion.
    func dragHover(_ valid: Bool, documents: Bool = false) {
        guard valid, visibility.collapsedGroup != nil,
              documents || visibility == .collapsePinned, !isExpanded else { cancelDwell(); return }
        guard pending == nil else { return }
        let token = generation
        pending = scheduler.schedule(after: 0.5) { [weak self] in
            guard let self, generation == token else { return }
            pending = nil; dragExpanded = true; didChange?()
        }
    }

    func endDrag() {
        cancelDwell()
        guard dragExpanded else { return }
        dragExpanded = false; didChange?()
    }

    private func cancelDwell() {
        generation = UUID(); pending?.cancel(); pending = nil
    }

    func stop() { cancelDwell(); didChange = nil }
}

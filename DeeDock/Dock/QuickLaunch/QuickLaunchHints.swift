import Foundation
import Observation

/// Per-panel number hints drawn over application icons while Quick Launch keys are on.
///
/// Hints are visible in two situations: throughout a Focus Dock session, and for a short period
/// after a Quick Launch shortcut targets this dock. The owner recomputes `numbers` whenever the
/// dock's entries change, so a hint never names an app that has moved or quit.
@MainActor @Observable
final class QuickLaunchHints {
    /// How long hints stay after a shortcut, long enough to read the numbers of neighbouring apps.
    static let flashDuration: Duration = .seconds(1.6)

    /// Copied from the shared Quick Launch preference. Off clears every hint.
    private(set) var isEnabled = false
    /// Item ID to one-based slot for the dock's current entries.
    private(set) var numbers: [String: Int] = [:]
    /// True while Focus Dock owns this panel.
    private(set) var isPersistent = false
    /// True during the short reveal after a shortcut.
    private(set) var isFlashing = false
    /// The item most recently opened by a shortcut, briefly emphasised among the hints.
    private(set) var lastTriggeredID: String?

    @ObservationIgnored private var flashTask: Task<Void, Never>?

    /// Whether any icon on this dock should draw its number now.
    var isVisible: Bool { isEnabled && (isPersistent || isFlashing) && !numbers.isEmpty }

    /// The digit to draw for an item, or nil when it has no slot or hints are hidden.
    func label(for itemID: String) -> String? {
        guard isVisible, let slot = numbers[itemID] else { return nil }
        return QuickLaunchSlots.label(for: slot)
    }

    /// Replaces the slot mapping. Equal input leaves observation untouched so layout passes stay cheap.
    func configure(enabled: Bool, assignments: [QuickLaunchAssignment]) {
        let mapped = enabled ? Dictionary(assignments.map { ($0.itemID, $0.slot) }, uniquingKeysWith: { first, _ in first }) : [:]
        if isEnabled != enabled { isEnabled = enabled }
        if numbers != mapped { numbers = mapped }
        if !enabled { hide() }
    }

    /// Shows hints for the whole Focus Dock session.
    func setPersistent(_ persistent: Bool) {
        if isPersistent != persistent { isPersistent = persistent }
    }

    /// Shows hints for `flashDuration`, restarting the deadline on a repeated shortcut.
    ///
    /// - Parameter itemID: The item a shortcut just opened, or nil when the slot was empty.
    func flash(triggered itemID: String?) {
        guard isEnabled else { return }
        flashTask?.cancel()
        lastTriggeredID = itemID
        isFlashing = true
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled, let self else { return }
            isFlashing = false
            lastTriggeredID = nil
            flashTask = nil
        }
    }

    /// Cancels a pending flash deadline and hides transient hints. Focus Dock hints are unaffected.
    func hide() {
        flashTask?.cancel()
        flashTask = nil
        if isFlashing { isFlashing = false }
        if lastTriggeredID != nil { lastTriggeredID = nil }
    }

    /// Ends every hint when the owning panel stops.
    func stop() {
        hide()
        isPersistent = false
        numbers = [:]
    }
}

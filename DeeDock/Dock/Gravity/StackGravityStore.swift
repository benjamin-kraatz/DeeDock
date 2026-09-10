import Foundation
import Observation

/// App-wide stack-gravity settings, Focus mute, and the current snap undo.
///
/// Persistence is independent of `DockSettings` so parallel slices do not share that document.
@MainActor @Observable
final class StackGravityStore {
    private(set) var document = StackGravityDocument()
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    /// True while a Focus Session is running or paused. Completed sessions do not mute gravity.
    private(set) var focusActive = false
    private(set) var undo: StackGravityUndo?
    private(set) var pendingSnap: StackGravityPendingSnap?
    @ObservationIgnored private let repository: StackGravityRepository

    init(repository: StackGravityRepository = StackGravityRepository()) {
        self.repository = repository
    }

    /// Strength after enable, Focus behavior, and validation. Zero turns pull and snap off.
    var effectiveStrength: CGFloat {
        guard document.isEnabled, !requiresReset else { return 0 }
        let strength = CGFloat(document.strength)
        guard focusActive else { return strength }
        switch document.focusBehavior {
        case .keep: return strength
        case .mute: return strength * StackGravityPhysics.focusMuteFactor
        case .disable: return 0
        }
    }

    var isEnabled: Bool { document.isEnabled }
    var strength: Double { document.strength }
    var focusBehavior: StackGravityFocusBehavior { document.focusBehavior }

    func start() {
        do {
            if let stored = try repository.load() {
                document = stored
            }
        } catch {
            requiresReset = true
            storageFailed = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !requiresReset, document.isEnabled != enabled else { return }
        document.isEnabled = enabled
        persist()
    }

    func setStrength(_ strength: Double) {
        var next = document
        next.strength = strength
        guard !requiresReset, let normalized = next.normalized, normalized != document else { return }
        document = normalized
        persist()
    }

    func setFocusBehavior(_ behavior: StackGravityFocusBehavior) {
        guard !requiresReset, document.focusBehavior != behavior else { return }
        document.focusBehavior = behavior
        persist()
    }

    func setFocusActive(_ active: Bool) {
        focusActive = active
    }

    /// Remembers a snap while the pointer is in a well. Cleared when the pointer leaves.
    func notePendingSnap(_ snap: StackGravityPendingSnap?) {
        pendingSnap = snap
    }

    /// Records undo after a snap actually changed this display's pins.
    func registerUndo(_ record: StackGravityUndo) {
        undo = record
        pendingSnap = nil
    }

    func dismissUndo() {
        undo = nil
    }

    /// Returns the matching undo and clears it so a second press cannot rewrite pins twice.
    func consumeUndo(for displayID: String) -> StackGravityUndo? {
        guard let undo, undo.displayID == displayID else { return nil }
        self.undo = nil
        return undo
    }

    func undo(for displayID: String) -> StackGravityUndo? {
        undo.flatMap { $0.displayID == displayID ? $0 : nil }
    }

    /// Replaces an unreadable document after an explicit reset.
    func reset() {
        repository.remove()
        document = StackGravityDocument()
        requiresReset = false
        storageFailed = false
        undo = nil
        pendingSnap = nil
    }

    private func persist() {
        do {
            try repository.save(document)
            storageFailed = false
        } catch {
            storageFailed = true
        }
    }
}

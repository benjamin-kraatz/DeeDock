import Foundation

/// How an active Focus Session changes stack gravity.
nonisolated enum StackGravityFocusBehavior: String, Codable, CaseIterable, Sendable {
    /// Leave pull and snap at the configured strength.
    case keep
    /// Keep a quarter of the configured strength so the dock stays quieter.
    case mute
    /// Turn pull and snap off until the session ends.
    case disable
}

/// App-wide stack-gravity preferences. Strength is 0...1; Settings shows it as a percent.
nonisolated struct StackGravityDocument: Codable, Equatable, Sendable {
    var version = 1
    var isEnabled = true
    var strength = 0.4
    var focusBehavior: StackGravityFocusBehavior = .mute

    var isValid: Bool {
        version == 1 && (0...1).contains(strength) && strength.isFinite
    }

    /// Snaps strength to 5% steps used by the Settings slider.
    var normalized: StackGravityDocument? {
        guard isValid else { return nil }
        var result = self
        result.strength = (strength * 20).rounded() / 20
        return result
    }
}

/// One reversible snap on a single display.
nonisolated struct StackGravityUndo: Equatable, Sendable {
    let displayID: String
    let previousPins: [DockPin]
    let stackName: String
}

/// Last snap proposal produced while the pointer was over a well.
nonisolated struct StackGravityPendingSnap: Equatable, Sendable {
    let displayID: String
    let stackName: String
    let pinIndex: Int
    let wellPinIndex: Int
}

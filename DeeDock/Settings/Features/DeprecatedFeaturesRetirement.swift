import Foundation

/// Turns off pre-1.0 personality features and writes the change.
///
/// Launch loads each store, then this coercion runs so existing installs that had
/// Sims, Focus breathing, Focus debt, Pin weather, Quarantine stamp, or Patch bay
/// enabled match new installs. Settings pages stay reachable for the removal notice.
enum DeprecatedFeaturesRetirement {
    /// Coerces every deprecated enable flag to `false` and persists when the value changes.
    ///
    /// Safe to call more than once. Stores that cannot write because their document is
    /// unreadable are left frozen; those loads already keep runtime effects off.
    @MainActor
    static func disableEnabledFlags(
        sims: DockSimsStore,
        focusBreathing: FocusBreathingStore,
        focusSession: FocusSessionController,
        pinWeather: PinWeatherStore,
        quarantine: QuarantineStampController,
        patchBay: PatchBayController
    ) {
        if sims.isEnabled { sims.setEnabled(false) }
        if focusBreathing.enabled { focusBreathing.setEnabled(false) }
        if focusSession.focusDebt.enabled { focusSession.configureFocusDebt(enabled: false) }
        if pinWeather.enabled { pinWeather.setEnabled(false) }
        if quarantine.enabled { quarantine.enabled = false }
        if patchBay.document.enabled { patchBay.setEnabled(false) }
    }
}

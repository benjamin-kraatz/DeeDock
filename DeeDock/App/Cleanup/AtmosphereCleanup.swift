import Foundation

/// Removes the preferences Atmosphere left behind, once, after DEE-157 removed it.
///
/// Atmosphere kept everything in two keys of DOKK's standard UserDefaults:
/// `atmosphere.settings.v1` (the JSON settings document, window light included) and
/// `atmosphere.decor.v1` (the Image Playground corner image, saved as PNG data of at most 256 px).
/// It wrote no files. The Image Playground sheet's temporary URL belongs to the system, and
/// Atmosphere copied the image into the second key before that URL expired. With no folder to
/// resolve, there is no Application Support path that could be guessed wrong.
///
/// `run()` removes exactly those two keys and nothing else. The completion flag is written last,
/// so an interrupted run repeats at the next launch.
nonisolated struct AtmosphereCleanup {
    /// Set once both keys are gone. The cleanup does nothing while it is set.
    static let completedKey = "cleanup.atmosphere.v1"

    /// Every key Atmosphere ever wrote.
    static let removedKeys = ["atmosphere.settings.v1", "atmosphere.decor.v1"]

    private let defaults: UserDefaults

    /// - Parameter defaults: The domain to clean. Tests pass a temporary suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Runs the cleanup off the main actor, matching the other launch cleanups.
    ///
    /// The task is not retained or cancelled: it finishes in moments, and an interrupted run is
    /// repeated at the next launch because the completion flag is written last.
    static func runInBackground() {
        Task.detached(priority: .utility) { AtmosphereCleanup().run() }
    }

    /// Removes Atmosphere's keys unless an earlier run finished. Running again after the flag is
    /// set changes nothing, so a key restored from a backup is left for the person.
    func run() {
        guard !defaults.bool(forKey: Self.completedKey) else { return }
        Self.removedKeys.forEach(defaults.removeObject(forKey:))
        defaults.set(true, forKey: Self.completedKey)
    }
}

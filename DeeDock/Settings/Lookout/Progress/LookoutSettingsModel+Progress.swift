import Foundation

/// The progress card's model and actions, on Lookout's Settings model.
extension LookoutSettingsModel {
    /// What the progress card shows: the engine's progress (`LookoutEngine.progress`, throttled), or the pinned
    /// sample in previews. Nil before setup, while Lookout is off, and while it waits for the model (the Files tab's
    /// download card and chip cover the download).
    var progress: LookoutProgressDisplay? {
        isPreview ? previewProgress : engine.progress
    }

    /// "Pause": reading waits; what's indexed stays searchable (`LookoutEngine.pause()`).
    func pauseReading() {
        engine.pause()
    }

    /// "Resume" after "Pause" (`LookoutEngine.resume()`).
    func resumeReading() {
        engine.resume()
    }
}

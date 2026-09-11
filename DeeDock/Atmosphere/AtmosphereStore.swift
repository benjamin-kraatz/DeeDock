import AppKit
import Observation
import ImageIO

/// Persists Atmosphere preferences and the optional system-generated corner image.
@MainActor @Observable
final class AtmosphereStore {
    var settings: AtmosphereSettings { didSet {
        if let data = try? JSONEncoder().encode(settings) { defaults?.set(data, forKey: Self.key) }
        changed?()
    } }
    private(set) var decorImage: NSImage?
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults?
    private static let key = "atmosphere.settings.v1"

    /// Passing nil creates an inert preview store without reading or writing preferences.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        decorImage = defaults?.data(forKey: "atmosphere.decor.v1").flatMap(NSImage.init(data:))
        settings = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(AtmosphereSettings.self, from: $0) } ?? .init()
        settings.density = settings.density.isFinite ? min(1, max(0, settings.density)) : 0.5
        settings.intensity = AtmosphereLimits.clamped(settings.intensity)
    }
    /// Copy the system sheet result into a bounded PNG before its temporary URL expires.
    func saveDecor(from url: URL) -> Bool {
        guard defaults != nil,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        defaults?.set(data, forKey: "atmosphere.decor.v1")
        decorImage = NSImage(cgImage: image, size: .zero)
        changed?()
        return true
    }

    func removeDecor() {
        defaults?.removeObject(forKey: "atmosphere.decor.v1")
        decorImage = nil
        changed?()
    }

}

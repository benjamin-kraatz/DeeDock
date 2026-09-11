import AppKit
import SwiftUI

/// Independent, app-wide preferences. No Dock Mode participates in this document.
struct AtmosphereSettings: Codable, Equatable {
    var enabled = false
    var preset: AtmospherePreset = .sixtyNine
    var source: AtmosphereColorSource = .manual
    var wallpaper: AtmosphereWallpaperMode = .gradient
    var panorama = false
    var density = 0.5
    /// Ambient wash strength on the 0…1 slider. The midpoint matches the original Atmosphere look.
    var intensity = AtmosphereLimits.defaultIntensity
    var idleOnly = false
    var manual = AtmospherePalette.default
    var moodPalette = AtmospherePalette.default
    var mood = ""

    enum CodingKeys: String, CodingKey {
        case enabled, preset, source, wallpaper, panorama, density, intensity, idleOnly, manual, moodPalette, mood
    }

    init() {}

    /// Documents saved before intensity keep every other field and receive the midpoint default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        preset = try container.decode(AtmospherePreset.self, forKey: .preset)
        source = try container.decode(AtmosphereColorSource.self, forKey: .source)
        wallpaper = try container.decode(AtmosphereWallpaperMode.self, forKey: .wallpaper)
        panorama = try container.decode(Bool.self, forKey: .panorama)
        density = try container.decode(Double.self, forKey: .density)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? AtmosphereLimits.defaultIntensity
        idleOnly = try container.decode(Bool.self, forKey: .idleOnly)
        manual = try container.decode(AtmospherePalette.self, forKey: .manual)
        moodPalette = try container.decode(AtmospherePalette.self, forKey: .moodPalette)
        mood = try container.decode(String.self, forKey: .mood)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(preset, forKey: .preset)
        try container.encode(source, forKey: .source)
        try container.encode(wallpaper, forKey: .wallpaper)
        try container.encode(panorama, forKey: .panorama)
        try container.encode(density, forKey: .density)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(idleOnly, forKey: .idleOnly)
        try container.encode(manual, forKey: .manual)
        try container.encode(moodPalette, forKey: .moodPalette)
        try container.encode(mood, forKey: .mood)
    }
}

/// Slider bounds and the wash derived from them. Intensity never shares a cap with Sims or soap bubbles.
enum AtmosphereLimits {
    static let defaultIntensity = 0.5
    static let intensityRange = 0.0...1.0

    /// Clamps a persisted slider value. Non-finite numbers fall back to the midpoint default.
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIntensity }
        return min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }

    /// Preset wash after the intensity slider. Zero stays a faint rim; one stays short of a full-screen overlay.
    ///
    /// Midpoint keeps the original 0.07 Minimal and 0.18 other-preset opacities. Below that the factor
    /// eases to 0.30. Above it, the factor rises to 2.20 so the high end is richer without covering the desktop.
    static func ambientOpacity(preset: AtmospherePreset, intensity: Double) -> Double {
        let base = preset == .minimal ? 0.07 : 0.18
        return base * intensityFactor(intensity)
    }

    /// Reduce Transparency rim width. Midpoint matches the original 2-point stroke.
    static func rimWidth(intensity: Double) -> CGFloat {
        CGFloat(1 + clamped(intensity) * 2)
    }

    private static func intensityFactor(_ intensity: Double) -> Double {
        let value = clamped(intensity)
        if value <= 0.5 {
            return 0.30 + value * 1.40
        }
        return 1.00 + (value - 0.5) * 2.40
    }
}

enum AtmospherePreset: String, Codable, CaseIterable {
    case sixtyNine, minimal, focus, party
    var title: LocalizedStringResource {
        switch self {
        case .sixtyNine: .atmosphere69
        case .minimal: .atmosphereMinimal
        case .focus: .atmosphereFocus
        case .party: .atmosphereParty
        }
    }
    var hasDecor: Bool { self == .sixtyNine || self == .party }
}

enum AtmosphereColorSource: String, Codable, CaseIterable {
    case manual, wallpaper, appIcon, mood
    var title: LocalizedStringResource {
        switch self {
        case .manual: .atmosphereManual
        case .wallpaper: .atmosphereWallpaper
        case .appIcon: .atmosphereAppIcon
        case .mood: .atmosphereMood
        }
    }
}

enum AtmosphereWallpaperMode: String, Codable, CaseIterable {
    case gradient, average, corners
    var title: LocalizedStringResource {
        switch self {
        case .gradient: .atmosphereGradient
        case .average: .atmosphereAverage
        case .corners: .atmosphereCorners
        }
    }
}

/// RGB components are stored as sRGB values, never platform archived colors.
nonisolated struct AtmosphereColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var color: Color {
        Color(red: Self.component(red), green: Self.component(green), blue: Self.component(blue))
    }
    private static func component(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    @MainActor init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .systemPink
        self.init(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }
}

nonisolated struct AtmospherePalette: Codable, Equatable, Sendable {
    var first: AtmosphereColor
    var second: AtmosphereColor
    static let `default` = Self(first: .init(0.85, 0.015, 0.12), second: .init(1, 0.25, 0.5))
}

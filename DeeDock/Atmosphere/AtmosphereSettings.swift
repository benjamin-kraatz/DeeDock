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
    var idleOnly = false
    var manual = AtmospherePalette.default
    var moodPalette = AtmospherePalette.default
    var mood = ""
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

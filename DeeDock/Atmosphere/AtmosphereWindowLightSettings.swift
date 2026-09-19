import SwiftUI

/// Opt-in window lighting, independent of the existing desktop color source.
struct AtmosphereWindowLightSettings: Codable, Equatable {
    var enabled = false
    var mode: AtmosphereWindowLightMode = .dzwei
    var glowing = false
    var rotates = true
}

nonisolated enum AtmosphereWindowLightMode: String, Codable, CaseIterable, Sendable {
    case average, dominant, random, daylight, dzwei

    var samplesWindow: Bool { self == .average || self == .dominant }

    var title: LocalizedStringResource {
        switch self {
        case .average: .atmosphereLightAverage
        case .dominant: .atmosphereLightDominant
        case .random: .atmosphereLightRandom
        case .daylight: .atmosphereLightDaylight
        case .dzwei: .atmosphereLightDzwei
        }
    }
}

/// Keeps dark content colorful and white content below a comfortable grey ceiling.
nonisolated enum AtmosphereWindowLightPalette {
    static let dzwei: [AtmosphereColor] = [
        .init(25 / 255.0, 143 / 255.0, 197 / 255.0),
        .init(226 / 255.0, 152 / 255.0, 48 / 255.0),
        .init(211 / 255.0, 86 / 255.0, 145 / 255.0)
    ]

    static func softened(_ color: AtmosphereColor) -> [AtmosphereColor] {
        let brightness = max(color.red, color.green, color.blue)
        // Continuous blending prevents flicker when content crosses the near-black threshold.
        let darkBlend = min(1, max(0, (0.16 - brightness) / 0.16))
        let whiteBlend = min(1, max(0, (min(color.red, color.green, color.blue) - 0.72) / 0.28))
        let grey = AtmosphereColor(0.48, 0.50, 0.53)
        let comfortable = mix(color, grey, whiteBlend)
        return dzwei.map { mix(comfortable, $0, darkBlend) }
    }

    /// A local-clock day/night cycle; no location access or sunrise estimate is involved.
    static func daylight(at date: Date) -> [AtmosphereColor] {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        let day = (1 + cos((hour - 13) * .pi / 12)) / 2
        return [mix(.init(0.16, 0.12, 0.10), .init(0.64, 0.68, 0.72), day)]
    }

    private static func mix(_ a: AtmosphereColor, _ b: AtmosphereColor, _ amount: Double) -> AtmosphereColor {
        .init(a.red + (b.red - a.red) * amount,
              a.green + (b.green - a.green) * amount,
              a.blue + (b.blue - a.blue) * amount)
    }
}

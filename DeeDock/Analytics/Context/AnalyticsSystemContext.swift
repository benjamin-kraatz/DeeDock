import AppKit

/// The chip family, so usage can be read against hardware class without a model table.
nonisolated enum AnalyticsChipFamily: String, AnalyticsToken {
    case appleSilicon = "apple_silicon", intel, unknown
}

/// The tier within an Apple silicon generation.
nonisolated enum AnalyticsChipTier: String, AnalyticsToken {
    case base, pro, max, ultra
}

/// The localization DOKK is running in.
nonisolated enum AnalyticsLanguage: String, AnalyticsToken {
    case en, de, other
}

nonisolated enum AnalyticsAppearance: String, AnalyticsToken {
    case light, dark
}

/// Facts about the Mac and its accessibility settings that every event carries.
///
/// The marketing version, build number, and macOS version are not repeated here: the SDK already
/// sends them as `$app_version`, `$app_build`, and `$os_version`.
enum AnalyticsSystemContext {
    static var properties: AnalyticsProperties {
        let workspace = NSWorkspace.shared
        var result: AnalyticsProperties = [
            "channel": AnalyticsValue(AnalyticsChannel.current),
            "app_language": AnalyticsValue(language),
            "appearance": AnalyticsValue(appearance),
            "reduce_motion": AnalyticsValue(workspace.accessibilityDisplayShouldReduceMotion),
            "reduce_transparency": AnalyticsValue(workspace.accessibilityDisplayShouldReduceTransparency),
            "increase_contrast": AnalyticsValue(workspace.accessibilityDisplayShouldIncreaseContrast),
        ]
        result.merge(chip)
        return result
    }

    private static var language: AnalyticsLanguage {
        Bundle.main.preferredLocalizations.first.flatMap { AnalyticsLanguage(rawValue: String($0.prefix(2))) } ?? .other
    }

    private static var appearance: AnalyticsAppearance {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    /// Parsed once: the chip cannot change while the app runs.
    private static let chip: AnalyticsProperties = chipProperties(brand: cpuBrand())

    /// Turns a brand string such as "Apple M3 Pro" into a family, a generation, and a tier.
    static func chipProperties(brand: String) -> AnalyticsProperties {
        let words = brand.split(separator: " ")
        guard words.first == "Apple",
              let model = words.dropFirst().first, model.hasPrefix("M"),
              let generation = Int(model.dropFirst()) else {
            return ["chip_family": AnalyticsValue(brand.contains("Intel") ? AnalyticsChipFamily.intel : .unknown)]
        }
        let tier = words.dropFirst(2).first.flatMap { AnalyticsChipTier(rawValue: $0.lowercased()) } ?? .base
        return ["chip_family": AnalyticsValue(AnalyticsChipFamily.appleSilicon),
                "chip_generation": AnalyticsValue(generation),
                "chip_tier": AnalyticsValue(tier)]
    }

    private static func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

import Foundation

/// How many installed and pinned apps have a Line glyph, and which public ones still lack one.
///
/// Installed and pinned apps are measured separately because they answer different questions:
/// installed coverage is what the Launcher shows, pinned coverage is what sits in a dock. An app
/// is counted once per group however many copies or displays it appears on.
nonisolated struct LineIconCoverage: Equatable, Sendable {
    var installedCount = 0
    var installedWithGlyphCount = 0
    var pinnedCount = 0
    var pinnedWithGlyphCount = 0
    /// Apps without a glyph, installed or pinned, that are not public. They are only counted.
    var unlistedMissingCount = 0
    /// Public apps without a glyph, installed or pinned, sorted.
    var missing: [AnalyticsPublicAppIdentifier] = []
    /// The pinned apps in ``missing``, sorted.
    var missingPinned: [AnalyticsPublicAppIdentifier] = []

    init() {}

    /// - Parameters:
    ///   - installed: apps found in the Applications folders.
    ///   - pinned: application pins from every display, duplicates included.
    ///   - hasGlyph: whether the Line catalog draws an app.
    ///   - publicApps: decides which missing apps may be named.
    init(installed: [ApplicationReference], pinned: [ApplicationReference],
         hasGlyph: (ApplicationReference) -> Bool, publicApps: AnalyticsPublicApps) {
        let installed = Self.unique(installed)
        let pinned = Self.unique(pinned)
        installedCount = installed.count
        pinnedCount = pinned.count

        var missingApps: [String: ApplicationReference] = [:]
        var missingPinnedIDs: Set<String> = []
        for application in installed {
            if hasGlyph(application) { installedWithGlyphCount += 1 } else { missingApps[application.id] = application }
        }
        for application in pinned {
            if hasGlyph(application) { pinnedWithGlyphCount += 1; continue }
            missingApps[application.id] = missingApps[application.id] ?? application
            missingPinnedIDs.insert(application.id)
        }

        var missing: [AnalyticsPublicAppIdentifier] = []
        var missingPinned: [AnalyticsPublicAppIdentifier] = []
        for (id, application) in missingApps {
            guard let identifier = publicApps.identifier(for: application) else {
                unlistedMissingCount += 1
                continue
            }
            missing.append(identifier)
            if missingPinnedIDs.contains(id) { missingPinned.append(identifier) }
        }
        // Two apps can share a bundle identifier at different paths; report it once.
        self.missing = Array(Set(missing)).sorted()
        self.missingPinned = Array(Set(missingPinned)).sorted()
    }

    /// The share of installed apps with a glyph, from 0 to 1. Zero when nothing is installed.
    var installedCoverage: Double { Self.ratio(installedWithGlyphCount, installedCount) }

    /// The share of pinned apps with a glyph, from 0 to 1. Zero when nothing is pinned.
    var pinnedCoverage: Double { Self.ratio(pinnedWithGlyphCount, pinnedCount) }

    private static func ratio(_ part: Int, _ whole: Int) -> Double {
        whole == 0 ? 0 : Double(part) / Double(whole)
    }

    private static func unique(_ applications: [ApplicationReference]) -> [ApplicationReference] {
        var seen: Set<String> = []
        return applications.filter { seen.insert($0.id).inserted }
    }
}

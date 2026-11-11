import Foundation

/// What Vapor recognized a folder as. The view layer maps each case to its localized chip text.
///
/// Raw values are stable: they are persisted nowhere today, but tests and debugging read them.
nonisolated enum VaporTag: String, CaseIterable, Sendable, Codable {
    case npmPackages
    case nextBuild
    case nuxtBuild
    case svelteKitBuild
    case turborepoCache
    case parcelCache
    case testCoverage
    case swiftPMBuild
    case xcodeBuildCache
    case xcodeBuildData
    case xcodeModuleCache
    case swiftPMCache
    case cargoBuild
    case cocoaPods
    case gradleCache
    case pythonCache
    /// `dist`, `build` or `out`. Tagged when dropped, never suggested: some projects commit them.
    case buildOutput

    /// Whether Finder suggestions may offer a folder with this tag.
    var isSuggested: Bool { self != .buildOutput }
}

/// The classification of a folder in the orb.
nonisolated enum VaporClassification: Equatable, Sendable {
    case known(VaporTag)
    /// Matches no rule. The panel shows an orange "Not a known cache" chip and a warning note.
    case unknown

    var tag: VaporTag? {
        if case .known(let tag) = self { return tag }
        return nil
    }

    var isKnown: Bool { tag != nil }
}

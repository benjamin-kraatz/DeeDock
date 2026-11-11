import Foundation

/// Maps Vapor's model values to localized copy. The model never holds display strings.
enum VaporCopy {
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    static func folderCount(_ count: Int) -> String {
        String(localized: .vaporFolderCount(count))
    }

    /// "3 folders · 1.8 GB", "3 folders · calculating…", or "Drop folders here" when empty.
    /// The orb's tooltip and the panel header's subtitle.
    static func summary(_ totals: VaporTotals) -> String {
        guard totals.count > 0 else { return String(localized: .vaporTooltipEmpty) }
        let size = totals.isPending ? String(localized: .vaporCalculating) : self.size(totals.bytes)
        return String(localized: .vaporJoined(folderCount(totals.count), size))
    }

    /// The orb's VoiceOver value: "3 folders, 1.8 GB" or "Empty".
    static func accessibilityValue(_ totals: VaporTotals) -> String {
        guard totals.count > 0 else { return String(localized: .vaporEmpty) }
        let size = totals.isPending ? String(localized: .vaporCalculating) : self.size(totals.bytes)
        return String(localized: .vaporAccessibilityJoined(folderCount(totals.count), size))
    }

    static func tag(_ classification: VaporClassification) -> LocalizedStringResource {
        guard let tag = classification.tag else { return .vaporUnknownTag }
        return self.tag(tag)
    }

    static func tag(_ tag: VaporTag) -> LocalizedStringResource {
        switch tag {
        case .npmPackages: .vaporTagNpmPackages
        case .nextBuild: .vaporTagNextBuild
        case .nuxtBuild: .vaporTagNuxtBuild
        case .svelteKitBuild: .vaporTagSvelteKitBuild
        case .turborepoCache: .vaporTagTurborepoCache
        case .parcelCache: .vaporTagParcelCache
        case .testCoverage: .vaporTagTestCoverage
        case .swiftPMBuild: .vaporTagSwiftPMBuild
        case .xcodeBuildCache: .vaporTagXcodeBuildCache
        case .xcodeBuildData: .vaporTagXcodeBuildData
        case .xcodeModuleCache: .vaporTagXcodeModuleCache
        case .swiftPMCache: .vaporTagSwiftPMCache
        case .cargoBuild: .vaporTagCargoBuild
        case .cocoaPods: .vaporTagCocoaPods
        case .gradleCache: .vaporTagGradleCache
        case .pythonCache: .vaporTagPythonCache
        case .buildOutput: .vaporTagBuildOutput
        }
    }

    static func refusal(_ refusal: VaporRefusal) -> LocalizedStringResource {
        switch refusal {
        case .notAFolder: .vaporRefusalNotAFolder
        case .package: .vaporRefusalPackage
        case .alreadyAdded(let name): .vaporRefusalAlreadyAdded(name)
        case .homeFolder: .vaporRefusalHome
        case .standardFolder(let name): .vaporRefusalStandard(name)
        case .systemLocation(let name): .vaporRefusalSystem(name)
        case .volumeRoot(let name): .vaporRefusalVolume(name)
        case .missing(let name): .vaporRefusalMissing(name)
        }
    }

    static func failure(_ failure: VaporStagingFailure) -> LocalizedStringResource {
        switch failure {
        case .permissionDenied: .vaporFailurePermission
        case .unsupportedVolume: .vaporFailureVolume
        case .missing: .vaporFailureMissing
        case .other: .vaporFailureOther
        }
    }

    /// The capsule's main text. Countdown and Undo are separate controls.
    static func status(_ kind: VaporStatus.Kind) -> String {
        switch kind {
        case .deleted(let count, let failed, _):
            let deleted = String(localized: .vaporStatusDeleted(count))
            guard failed > 0 else { return deleted }
            return String(localized: .vaporJoined(deleted, String(localized: .vaporStatusSomeFailed(failed))))
        case .freed(let bytes, _, let failed):
            // The capsule draws its own green check in front of this.
            let freed = String(localized: .vaporStatusFreed(size(bytes)))
            guard failed > 0 else { return freed }
            return String(localized: .vaporJoined(freed, String(localized: .vaporStatusSomeFailed(failed))))
        case .failed(let count):
            return String(localized: .vaporStatusFailed(count))
        case .notRestored(let count):
            return String(localized: .vaporStatusNotRestored(count))
        }
    }

    /// "4 caches in dokk-web", "node_modules · npm packages" while a bubble is hovered.
    static func suggestionCapsule(count: Int, folder: URL?, hovered: VaporSuggestion?) -> String {
        if let hovered {
            return String(localized: .vaporJoined(hovered.name, String(localized: tag(hovered.tag))))
        }
        let caches = String(localized: .vaporCacheCount(count))
        return String(localized: .vaporCachesIn(caches, folder?.lastPathComponent ?? ""))
    }
}

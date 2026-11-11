#if DEBUG
import CoreGraphics
import Foundation

/// Deterministic sample data for Vapor's previews. Nothing here reads the disk, Finder or
/// preferences: the store is inert and the measurer and deleter do nothing.
enum VaporPreviewData {
    static let home = URL(fileURLWithPath: "/Users/preview")

    private struct IdleMeasurer: VaporMeasuring {
        func measure(_ url: URL) async -> VaporMeasurement { .pending }
    }

    private struct IdleDeleter: VaporDeleting {
        func stage(_ requests: [VaporStageRequest]) async -> [VaporStageOutcome] { [] }
        func restore(_ entries: [VaporLedgerEntry]) async -> [VaporRestoreOutcome] { [] }
        func remove(_ entries: [VaporLedgerEntry]) async -> [UUID] { [] }
        func recover() async -> Int { 0 }
    }

    static func folder(_ path: String, _ tag: VaporTag?, bytes: Int64? = nil, files: Int = 0,
                       unreadable: Bool = false, failure: VaporStagingFailure? = nil) -> VaporFolder {
        let measurement: VaporMeasurement = unreadable ? .unreadable
            : bytes.map { .measured(bytes: $0, files: files) } ?? .pending
        return VaporFolder(url: home.appendingPathComponent(path), classification: tag.map(VaporClassification.known) ?? .unknown,
                           measurement: measurement, failure: failure)
    }

    static let mixed: [VaporFolder] = [
        folder("dev/dokk-web/node_modules", .npmPackages, bytes: 812_000_000, files: 61_204),
        folder("dev/dokk-web/.next", .nextBuild, bytes: 236_000_000, files: 4_918),
        folder("Library/Developer/Xcode/DerivedData", .xcodeBuildCache, bytes: 7_400_000_000, files: 38_104),
        folder("dev/old-site", nil, bytes: 41_000_000, files: 822),
    ]

    static let calculating: [VaporFolder] = [
        folder("dev/dokk-web/node_modules", .npmPackages),
        folder("dev/api/target", .cargoBuild, bytes: 1_200_000_000, files: 9_310),
        folder("dev/locked-cache", nil, unreadable: true),
    ]

    static let failed: [VaporFolder] = [
        folder("dev/shared/node_modules", .npmPackages, bytes: 412_000_000, files: 30_112, failure: .permissionDenied),
    ]

    static let finderFolder = home.appendingPathComponent("dev/dokk-web")

    static let suggestions: [VaporSuggestion] = [
        VaporSuggestion(url: finderFolder.appendingPathComponent(".next"), tag: .nextBuild),
        VaporSuggestion(url: finderFolder.appendingPathComponent(".turbo"), tag: .turborepoCache),
        VaporSuggestion(url: finderFolder.appendingPathComponent("coverage"), tag: .testCoverage),
        VaporSuggestion(url: finderFolder.appendingPathComponent("node_modules"), tag: .npmPackages),
    ]

    /// A controller in a fixed state. Times are relative to a fixed reference date.
    static func controller(_ folders: [VaporFolder] = [], status: VaporStatus? = nil, panel: Bool = false,
                           suggestions: [VaporSuggestion] = [], permission: VaporAutomationPermission = .granted,
                           refusal: VaporRefusal? = nil, opensLeft: Bool = false, reduceTransparency: Bool = false)
        -> VaporController {
        let controller = VaporController(dependencies: .init(
            store: VaporStore(defaults: nil), home: home, policy: VaporDropPolicy(home: home),
            measurer: IdleMeasurer(), deleter: IdleDeleter()))
        controller.loadPreviewState(folders: folders, status: status, isPanelOpen: panel,
                                    finderFolder: suggestions.isEmpty ? nil : finderFolder, finderItems: suggestions,
                                    permission: permission, refusal: refusal)
        controller.opensLeft = opensLeft
        controller.badgeCorner = opensLeft ? .topTrailing : .topLeading
        controller.reduceTransparency = reduceTransparency
        controller.lighting = VaporGeometry.lighting(orbCenter: CGPoint(x: 1300, y: 300),
                                                     displayFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        return controller
    }
}
#endif

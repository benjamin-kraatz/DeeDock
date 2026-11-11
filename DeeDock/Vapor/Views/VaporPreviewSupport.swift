#if DEBUG
import CoreGraphics
import Foundation
import SwiftUI

/// Deterministic sample data for Vapor's previews and snapshot tests. Nothing here reads the
/// disk, Finder or preferences: the store is inert and the measurer and deleter do nothing.
enum VaporPreviewData {
    static let home = URL(fileURLWithPath: "/Users/preview")

    /// Where the display's lamp sits relative to the orb.
    enum Lamp {
        /// The orb is on the right of its display, so the lamp is up and to its left.
        case upperLeft
        /// The orb is on the left of its display.
        case upperRight

        var orbCenter: CGPoint {
            switch self {
            case .upperLeft: CGPoint(x: 1300, y: 300)
            case .upperRight: CGPoint(x: 210, y: 300)
            }
        }
    }

    static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 950)

    private struct IdleMeasurer: VaporMeasuring {
        func measure(_ url: URL) async -> VaporMeasurement { .pending }
    }

    private struct IdleDeleter: VaporDeleting {
        func stage(_ requests: [VaporStageRequest]) async -> [VaporStageOutcome] { [] }
        func restore(_ entries: [VaporLedgerEntry]) async -> [VaporRestoreOutcome] { [] }
        func remove(_ entries: [VaporLedgerEntry]) async -> [UUID] { [] }
        func recover() async -> Int { 0 }
    }

    /// A folder with a stable id derived from its path, so previews and snapshots are repeatable.
    static func folder(_ path: String, _ tag: VaporTag?, bytes: Int64? = nil, files: Int = 0,
                       unreadable: Bool = false, failure: VaporStagingFailure? = nil) -> VaporFolder {
        let measurement: VaporMeasurement = unreadable ? .unreadable
            : bytes.map { .measured(bytes: $0, files: files) } ?? .pending
        return VaporFolder(id: stableID(path), url: home.appendingPathComponent(path),
                           classification: tag.map(VaporClassification.known) ?? .unknown,
                           measurement: measurement, failure: failure)
    }

    private static func stableID(_ path: String) -> UUID {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in path.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: hash >> (index * 8))
            bytes[index + 8] = UInt8(truncatingIfNeeded: (hash &* 31) >> (index * 8))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
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

    /// Six folders of very different sizes, for the tumbling pile.
    static let pile: [VaporFolder] = [
        folder("Library/Developer/Xcode/DerivedData/DOKK-fjqk", .xcodeBuildData, bytes: 9_800_000_000, files: 201_334),
        folder("dev/dokk-web/node_modules", .npmPackages, bytes: 1_310_000_000, files: 94_210),
        folder("dev/dokk-web/.next", .nextBuild, bytes: 486_000_000, files: 8_912),
        folder("dev/dokk-web/.turbo", .turborepoCache, bytes: 211_000_000, files: 3_104),
        folder("dev/dokk-web/coverage", .testCoverage, bytes: 12_600_000, files: 1_288),
        folder("dev/dokk-web/public", nil, bytes: 22_400_000, files: 146),
    ]

    /// The panel's mix: known and unknown folders, one still measuring, one that failed.
    static let panel: [VaporFolder] = [
        folder("dev/dokk-web/node_modules", .npmPackages, bytes: 1_310_000_000, files: 94_210),
        folder("Library/Developer/Xcode/DerivedData", .xcodeBuildCache),
        folder("dev/dokk-web/public", nil, bytes: 22_400_000, files: 146),
        folder("dev/shared/.turbo", .turborepoCache, bytes: 211_000_000, files: 3_104, failure: .permissionDenied),
    ]

    static let finderFolder = home.appendingPathComponent("dev/dokk-web")

    static let suggestions: [VaporSuggestion] = [
        VaporSuggestion(url: finderFolder.appendingPathComponent(".next"), tag: .nextBuild),
        VaporSuggestion(url: finderFolder.appendingPathComponent(".turbo"), tag: .turborepoCache),
        VaporSuggestion(url: finderFolder.appendingPathComponent("coverage"), tag: .testCoverage),
        VaporSuggestion(url: finderFolder.appendingPathComponent("node_modules"), tag: .npmPackages),
    ]

    /// A drag 60 pt beyond the orb's edge, up and to the left.
    static var nearbyDrag: VaporDropHover {
        let orb = Lamp.upperLeft.orbCenter
        let radius = VaporGeometry.orbDiameter / 2 + 60
        let point = CGPoint(x: orb.x - radius * 0.8, y: orb.y + radius * 0.6)
        return VaporDropHover(proximity: VaporGeometry.dropProximity(point: point, orbCenter: orb), isOverPanel: false)
    }

    /// A drag right over the orb.
    static var overOrbDrag: VaporDropHover {
        let orb = Lamp.upperLeft.orbCenter
        let point = CGPoint(x: orb.x - 20, y: orb.y + 10)
        return VaporDropHover(proximity: VaporGeometry.dropProximity(point: point, orbCenter: orb), isOverPanel: false)
    }

    /// A controller in a fixed state.
    static func controller(_ folders: [VaporFolder] = [], status: VaporStatus? = nil, panel: Bool = false,
                           suggestions: [VaporSuggestion] = [], permission: VaporAutomationPermission = .granted,
                           refusal: VaporRefusal? = nil, opensLeft: Bool = false, reduceTransparency: Bool = false,
                           reduceMotion: Bool = false, lamp: Lamp = .upperLeft,
                           hold: VaporHoldProgress = VaporHoldProgress()) -> VaporController {
        let controller = VaporController(dependencies: .init(
            store: VaporStore(defaults: nil), home: home, policy: VaporDropPolicy(home: home),
            measurer: IdleMeasurer(), deleter: IdleDeleter()))
        controller.loadPreviewState(folders: folders, status: status, isPanelOpen: panel,
                                    finderFolder: suggestions.isEmpty ? nil : finderFolder, finderItems: suggestions,
                                    permission: permission, refusal: refusal, hold: hold)
        controller.opensLeft = opensLeft
        controller.badgeCorner = opensLeft ? .topTrailing : .topLeading
        controller.reduceTransparency = reduceTransparency
        controller.reduceMotion = reduceMotion
        controller.lighting = VaporGeometry.lighting(orbCenter: lamp.orbCenter, displayFrame: display)
        return controller
    }

    /// A pile engine already holding the controller's folders, settled.
    static func settledPile(for controller: VaporController, seed: UInt64 = 7) -> VaporPileEngine {
        let engine = VaporPileEngine(seed: seed)
        engine.sync(folders: controller.folders, addition: nil, deletion: nil, isStaging: false, reduceMotion: true)
        return engine
    }
}

/// A desktop-like wallpaper behind previews, so glass and shadows have something to sit on.
/// The colours follow the mockup's wallpaper for the current appearance.
struct VaporPreviewBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            (dark ? Color(red: 0x0C / 255, green: 0x14 / 255, blue: 0x24 / 255)
                : Color(red: 0xE8 / 255, green: 0xEE / 255, blue: 0xF8 / 255))
            RadialGradient(colors: [dark ? Color(red: 0x3A / 255, green: 0x1F / 255, blue: 0x4C / 255)
                                        : Color(red: 0xF1 / 255, green: 0xCD / 255, blue: 0xE0 / 255), .clear],
                           center: UnitPoint(x: 0.18, y: 0.2), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [dark ? Color(red: 0x1B / 255, green: 0x2A / 255, blue: 0x4A / 255)
                                        : Color(red: 0xBC / 255, green: 0xD3 / 255, blue: 0xF5 / 255), .clear],
                           center: UnitPoint(x: 0.85, y: 0.75), startRadius: 0, endRadius: 520)
        }
    }
}
#endif

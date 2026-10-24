#if DEBUG
import SwiftUI

/// Sample uninstall sessions frozen in one state. They read no files and start nothing; sizes for the
/// Developer app are the ones measured in the 24 Oct 2026 spike.
enum HubUninstallPreviewData {
    private static let library = "/Users/preview/Library"

    static func developer(phase: AppUninstallSession.Phase = .review, fullDiskAccess: Bool = false,
                          accessStage: AppUninstallSession.AccessStage = .idle,
                          itemProgress: [String: AppUninstallSession.ItemProgress] = [:],
                          appProgress: AppUninstallSession.ItemProgress? = nil) -> AppUninstallSession {
        let target = AppUninstallTarget(
            url: URL(fileURLWithPath: "/Applications/Developer.app"), name: "Developer",
            bundleIdentifier: "developer.apple.wwdc-Release", version: "11.2", source: .appStore, ownedByRoot: true,
            teamIdentifier: "9JA89QQLNQ", appGroups: ["group.developer.apple.wwdc"],
            embeddedIdentifiers: ["developer.apple.wwdc-Release.Developer-Widget"], helperIdentifiers: [],
            names: ["Developer"], hasSystemExtensions: false, vendorUninstaller: nil, byteCount: 16_200_000)
        var items = [
            item("Containers/developer.apple.wwdc-Release", .container),
            item("Containers/developer.apple.wwdc-Release.Developer-Widget", .extensionContainer),
            item("Group Containers/group.developer.apple.wwdc", .groupContainer, match: .appGroup),
            item("Containers/com.example.apple-samplecode.SwiftChartsWWDC24", .container, match: .similarName),
        ]
        for index in items.indices where items[index].match != .similarName { items[index].isProtected = !fullDiskAccess }
        let sizes: [Int64] = [7_100_000, 700_000, 23_600_000, 1_400_000]
        return AppUninstallSession(preview: target, leftovers: items, measures: measures(items, sizes), phase: phase,
                                   accessStage: accessStage, itemProgress: itemProgress, appProgress: appProgress)
    }

    static func warp() -> AppUninstallSession {
        let target = AppUninstallTarget(
            url: URL(fileURLWithPath: "/Applications/Warp.app"), name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable",
            version: "0.2026.10.21", source: .downloaded, ownedByRoot: false, teamIdentifier: "2BBY89MBSN",
            appGroups: ["2BBY89MBSN.dev.warp"], embeddedIdentifiers: [], helperIdentifiers: [], names: ["Warp"],
            hasSystemExtensions: false, vendorUninstaller: nil, byteCount: 412_000_000)
        var items = [
            item("Application Support/dev.warp.Warp-Stable", .applicationSupport),
            item("Caches/dev.warp.Warp-Stable", .caches), item("Preferences/dev.warp.Warp-Stable.plist", .preferences),
            item("Saved Application State/dev.warp.Warp-Stable.savedState", .savedState),
            item("Logs/dev.warp.Warp-Stable", .logs),
            item("Group Containers/2BBY89MBSN.dev.warp", .groupContainer, match: .appGroup),
            AppLeftover(url: URL(fileURLWithPath: "/Users/preview/.warp"), kind: .homeFolder, match: .similarName, domain: .user),
        ]
        items[5].isProtected = true
        let sizes: [Int64] = [86_400_000, 211_000_000, 82_000, 300_000, 4_600_000, 12_800_000, 3_100_000]
        let session = AppUninstallSession(preview: target, leftovers: items, measures: measures(items, sizes), phase: .review,
                                          pinnedDisplayCount: 2, isRunning: true)
        session.relatedExpanded = true
        return session
    }

    static func netGuard() -> AppUninstallSession {
        let target = AppUninstallTarget(
            url: URL(fileURLWithPath: "/Applications/NetGuard.app"), name: "NetGuard", bundleIdentifier: "com.netguard.app",
            version: "4.8", source: .downloaded, ownedByRoot: false, teamIdentifier: nil, appGroups: [],
            embeddedIdentifiers: [], helperIdentifiers: ["com.netguard.helper"], names: ["NetGuard"],
            hasSystemExtensions: true, vendorUninstaller: URL(fileURLWithPath: "/Applications/NetGuard Uninstaller.app"),
            byteCount: 58_000_000)
        let items = [
            item("Application Support/com.netguard.app", .applicationSupport), item("Caches/com.netguard.app", .caches),
            AppLeftover(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.netguard.helper.plist"), kind: .backgroundHelper,
                        match: .bundleIdentifier, domain: .allUsers),
        ]
        return AppUninstallSession(preview: target, leftovers: items, measures: measures(items, [6_200_000, 18_000_000, 4_000]),
                                   phase: .review, pinnedDisplayCount: 1)
    }

    private static func item(_ path: String, _ kind: AppLeftover.Kind, match: AppLeftover.Match = .bundleIdentifier) -> AppLeftover {
        AppLeftover(url: URL(fileURLWithPath: "\(library)/\(path)"), kind: kind, match: match, domain: .user)
    }

    private static func measures(_ items: [AppLeftover], _ sizes: [Int64]) -> [String: AppLeftoverMeasure] {
        Dictionary(uniqueKeysWithValues: zip(items, sizes).compactMap { item, size in
            item.isProtected ? nil : (item.id, AppLeftoverMeasure.size(size))
        })
    }
}

/// A sheet on a dark Hub-like backdrop, the width of the Apps tab.
private struct HubUninstallPreviewStage: View {
    let session: AppUninstallSession

    var body: some View {
        // The fixture model's launcher is inert: no discovery, preferences, or launches.
        let uninstaller = HubAppsPreviewData.model().uninstaller
        HubUninstallSheet(session: session, uninstaller: uninstaller, maxHeight: 560)
            .frame(width: 900, height: 600, alignment: .top)
            .background(LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }
}

#Preview("App Store app, no Full Disk Access") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.developer())
}

#Preview("App Store app, relaunch for access") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.developer(accessStage: .openedSettings))
}

#Preview("App Store app, waiting for password") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.developer(phase: .working(.waitingForPassword), fullDiskAccess: true,
                                                                        appProgress: .working))
}

#Preview("Password cancelled") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.developer(phase: .stopped(.passwordCancelled)))
}

#Preview("Done, data stayed") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.developer(phase: .done(.init(
        movedItems: 0, bytes: 16_200_000, failedItems: 0, protectedItems: 3, hasSystemExtensions: false,
        helpersKeepRunning: false))))
}

#Preview("Downloaded, open, pinned") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.warp())
}

#Preview("System extension, German, light") {
    HubUninstallPreviewStage(session: HubUninstallPreviewData.netGuard())
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.light)
}
#endif

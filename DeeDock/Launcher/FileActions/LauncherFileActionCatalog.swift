import Foundation

/// Builds chooser rows from installed apps, pinned Shortcuts, and bookmarked folders.
///
/// Ranking is declared support and a stable name order. File contents are not read.
enum LauncherFileActionCatalog {
    static func items(
        inputs: [LauncherFileInput],
        applications: [LauncherApplication],
        shortcuts: [ActionTile],
        destinations: [LauncherFileDestination],
        destinationAvailable: (LauncherFileDestination) -> Bool,
        compatibility: LauncherFileCompatibility.Snapshot?
    ) -> [LauncherFileActionItem] {
        let available = inputs.filter(\.isAvailable)
        let urls = available.map(\.url)
        var items: [LauncherFileActionItem] = []
        items.append(contentsOf: applicationItems(
            applications: applications, urls: urls, inputs: available, compatibility: compatibility
        ))
        items.append(contentsOf: shortcutItems(shortcuts))
        items.append(contentsOf: destinationItems(destinations, available: destinationAvailable))
        items.append(LauncherFileActionItem(
            id: .chooseFolder,
            title: String(localized: .launcherFileChooseFolder),
            subtitle: .launcherFileChooseFolderDetail,
            symbol: "folder.badge.plus",
            support: .all,
            unsupportedNames: [],
            unavailable: available.isEmpty,
            rank: 400,
            application: nil
        ))
        return items.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            let order = lhs.title.localizedStandardCompare(rhs.title)
            return order == .orderedSame ? lhs.id.hashValue < rhs.id.hashValue : order == .orderedAscending
        }
    }

    static func matching(_ items: [LauncherFileActionItem], query: String) -> [LauncherFileActionItem] {
        let normalized = LauncherApplication.normalize(query)
        guard !normalized.isEmpty else {
            return items.filter { $0.support != .none }
        }
        return items.filter { item in
            if LauncherApplication.normalize(item.title).contains(normalized) { return true }
            if case .openWith = item.id, let application = item.application {
                return application.score(normalized) != nil
            }
            return false
        }
    }

    private static func applicationItems(
        applications: [LauncherApplication],
        urls: [URL],
        inputs: [LauncherFileInput],
        compatibility: LauncherFileCompatibility.Snapshot?
    ) -> [LauncherFileActionItem] {
        guard let compatibility, !urls.isEmpty else { return [] }
        return applications.compactMap { application in
            let result = LauncherFileCompatibility.support(
                for: application.reference, urls: urls, in: compatibility
            )
            let support: LauncherFileSupport
            let rank: Int
            if result.unsupported.isEmpty {
                support = .all
                rank = 0
            } else if result.supported.isEmpty {
                support = .none
                rank = 500
            } else {
                support = .mixed
                rank = 100
            }
            let unsupportedNames = inputs.filter { input in
                result.unsupported.contains(input.url.standardizedFileURL)
            }.map(\.name)
            return LauncherFileActionItem(
                id: .openWith(application.id),
                title: application.reference.name,
                subtitle: support == .all ? .launcherFileOpenWithApp
                    : support == .mixed ? .launcherFileOpenWithMixed(result.supported.count, urls.count)
                    : .launcherFileOpenWithNone,
                symbol: "app",
                support: support,
                unsupportedNames: unsupportedNames,
                unavailable: support == .none,
                rank: rank,
                application: application
            )
        }
    }

    private static func shortcutItems(_ shortcuts: [ActionTile]) -> [LauncherFileActionItem] {
        shortcuts.map { tile in
            LauncherFileActionItem(
                id: .shortcut(tile.id),
                title: tile.name,
                subtitle: tile.acceptsFiles ? .launcherFilePassToShortcut : .launcherFilePassToShortcutUnconfigured,
                symbol: "bolt",
                support: .unknown,
                unsupportedNames: [],
                unavailable: false,
                rank: tile.acceptsFiles ? 200 : 250,
                application: nil
            )
        }
    }

    private static func destinationItems(
        _ destinations: [LauncherFileDestination],
        available: (LauncherFileDestination) -> Bool
    ) -> [LauncherFileActionItem] {
        destinations.map { destination in
            let ready = available(destination)
            return LauncherFileActionItem(
                id: .copyTo(destination.id),
                title: destination.name,
                subtitle: ready ? .launcherFileCopyToFolder : .launcherFileDestinationUnavailable,
                symbol: "folder",
                support: ready ? .all : .none,
                unsupportedNames: [],
                unavailable: !ready,
                rank: ready ? 300 : 350,
                application: nil
            )
        }
    }
}

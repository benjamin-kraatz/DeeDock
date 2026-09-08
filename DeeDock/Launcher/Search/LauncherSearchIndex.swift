import Foundation

/// Ordinary search is deterministic metadata matching. No provider may discover, capture, or activate here.
nonisolated enum LauncherSearchIndex {
    @concurrent static func results(_ input: LauncherSearchInput, windows: [WindowSearchSource]) async -> [LauncherSearchResult] {
        let query = LauncherApplication.normalize(String(input.query.prefix(200)))
        var results: [LauncherSearchResult] = []
        let appOnly = (input.kind == .all || input.kind == .application) && input.options.filter != .all
        if input.kind == .all || input.kind == .application {
            for app in input.applications {
                guard !Task.isCancelled else { return [] }
                switch input.options.filter {
                case .all: break
                case .running: guard input.options.running.contains(app.id) else { continue }
                case .pinned: guard input.options.pinned.contains(app.id) else { continue }
                case .recent: guard input.options.visits[app.id] != nil else { continue }
                }
                if let score = app.score(query) {
                    results.append(LauncherSearchResult(id: .application(app.id), kind: .application,
                        title: app.reference.name, source: app.reference.url.path, action: .unifiedOpenApp,
                        score: score, tieBreak: "0" + app.id, application: app))
                }
            }
        }
        if !appOnly && (input.kind == .all || input.kind == .window) {
            let matches = await WindowSearchIndex.results(query: query, scope: .live, sources: windows,
                snapshots: [], owners: [:], date: nil, saved: [], images: [])
            for match in matches {
                guard let source = match.source, source.window != nil || source.candidate != nil else { continue }
                results.append(LauncherSearchResult(id: .window(match.id), kind: .window,
                    title: match.title, source: source.applicationName + " · " + String(localized: .windowSearchMetadataEvidence),
                    action: source.window == nil ? .unifiedWindowUnavailable : .unifiedShowWindow,
                    score: LauncherApplication.normalize(match.title) == query ? 1 : 35,
                    tieBreak: "1" + match.id.uuidString, window: source, unavailable: source.window == nil))
            }
        }
        if !appOnly && (input.kind == .all || input.kind == .capsule) {
            let matches = await WindowSearchIndex.results(query: query, scope: .saved, sources: [],
                snapshots: [], owners: [:], date: nil, saved: input.capsules, images: [])
            results += matches.map { match in
                LauncherSearchResult(id: .capsule(match.id), kind: .capsule, title: match.title,
                    source: String(localized: match.evidence.label) + " · " + match.excerpt,
                    action: .unifiedOpenCapsule, score: LauncherApplication.normalize(match.title) == query ? 1 : 40,
                    tieBreak: "2" + match.id.uuidString)
            }
        }
        func append(_ id: LauncherSearchID, kind: LauncherSearchKind, name: String, source: String,
                    action: LocalizedStringResource, key: String) {
            guard !appOnly, input.kind == .all || input.kind == kind else { return }
            let normalized = LauncherApplication.normalize(name)
            let terms = query.split(whereSeparator: \.isWhitespace)
            guard terms.allSatisfy({ normalized.contains($0) }) else { return }
            let score = normalized == query ? 1 : normalized.hasPrefix(query) ? 15 : 30
            results.append(LauncherSearchResult(id: id, kind: kind, title: name, source: source,
                action: action, score: score, tieBreak: key))
        }
        for item in input.shelf {
            append(.shelf(item.id), kind: .shelf, name: item.name, source: String(localized: .unifiedShelfReference) + " · " + item.url.path,
                   action: .unifiedOpenFile, key: "3" + item.id.uuidString)
        }
        for tile in input.shortcuts {
            append(.shortcut(tile.id), kind: .shortcut, name: tile.name, source: String(localized: .unifiedPinnedShortcut),
                   action: .unifiedRunShortcut, key: "4" + tile.id.uuidString)
        }
        for mode in input.modes {
            append(.mode(mode.id), kind: .mode, name: mode.name, source: String(localized: .unifiedModeSource),
                   action: .unifiedSwitchMode, key: "5" + mode.id.uuidString)
        }
        guard !Task.isCancelled else { return [] }
        for index in results.indices {
            guard let app = results[index].application else { continue }
            switch input.options.grouping {
            case .none: break
            case .category: results[index].group = String(localized: LauncherCategory.title(app.category))
            case .letter: results[index].group = String(app.reference.name.prefix(1)).uppercased()
            }
        }
        return results.sorted {
            // App sections retain their browsing order in both layouts; other kinds stay compact below them.
            if ($0.application != nil) != ($1.application != nil) { return $0.application != nil }
            if $0.group != $1.group { return $0.group.localizedStandardCompare($1.group) == .orderedAscending }
            if $0.score != $1.score { return $0.score < $1.score }
            if let a = $0.application, let b = $1.application {
                let av = input.options.visits[a.id], bv = input.options.visits[b.id]
                if input.options.sort == .frequent, (av?.count ?? 0) != (bv?.count ?? 0) {
                    return (av?.count ?? 0) > (bv?.count ?? 0)
                }
                if input.options.sort == .recent, av?.lastOpened != bv?.lastOpened {
                    return (av?.lastOpened ?? .distantPast) > (bv?.lastOpened ?? .distantPast)
                }
            }
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.tieBreak < $1.tieBreak : order == .orderedAscending
        }
    }
}

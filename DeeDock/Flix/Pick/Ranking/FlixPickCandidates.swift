import Foundation
import UniformTypeIdentifiers

/// Everything the ranking needs about one picker, as values read on the main actor.
struct FlixPickContext {
    var kind: FlixPickPickerKind
    /// The app's name as macOS supplies it; never translated.
    var appName: String
    var types: FlixPickDocumentTypes
    /// Flix Files' history, newest first.
    var items: [FlixItem]
    /// What was picked in this app's pickers before, by standardized path.
    var picks: [String: FlixPickMemory.Entry]
    /// Drops on this app by drag memory kind.
    var dropCounts: [String: Int]
    var threads: [FlixThread]
    /// Items the sensitive guard flagged; never suggested.
    var sensitive: Set<FlixItem.ID>
    var hidesNoise: Bool
    var home: String = NSHomeDirectory()
    var now: Date
}

/// Builds Flix Pick's rows from what Flix Files already knows: its history, drag memory, its
/// Threads, and what was picked in this app before.
///
/// **Open pickers** list files: history rows that fit the app's declared types (``FlixPickDocumentTypes``;
/// no filter when it declares none), plus files picked here before that the history no longer
/// lists. Links, apps, noise, and files the sensitive guard flagged are never suggested; folders
/// only when the app declares it opens folders. **Save pickers** list folders: where the person
/// saved through this app's picker before, the folders holding recent files that fit the app,
/// folders where files were saved or created lately, and folders opened lately.
///
/// Nothing here touches the disk or another app: existence is checked afterwards, off the main
/// actor and only where the read policy allows (`FlixPickCoordinator`).
enum FlixPickCandidates {
    /// History rows looked at per picker; the newest are the likely ones.
    static let scanned = 800

    /// The best `limit` rows, highest score first.
    static func rows(for context: FlixPickContext, limit: Int = FlixPickRanker.limit) -> [FlixPickRow] {
        switch context.kind {
        case .open: files(for: context, limit: limit)
        case .save: folders(for: context, limit: limit)
        }
    }

    /// Standardized paths never suggested, whichever source names them: every history row the
    /// sensitive guard flagged (not only the scanned ones, since a learned pick may name one).
    private static func sensitivePaths(_ context: FlixPickContext) -> Set<String> {
        guard !context.sensitive.isEmpty else { return [] }
        return Set(context.items.compactMap { item in
            context.sensitive.contains(item.id) ? item.path.map(FlixPaths.standardized) : nil
        })
    }

    /// Whether a path from any source may be suggested: not flagged sensitive, not noise.
    private static func allowed(_ path: String, sensitive: Set<String>, context: FlixPickContext) -> Bool {
        !sensitive.contains(FlixPaths.standardized(path)) && !(context.hidesNoise && FlixNoiseRules.isNoise(path: path))
    }

    // MARK: Open

    private static func files(for context: FlixPickContext, limit: Int) -> [FlixPickRow] {
        var candidates: [(id: FlixItem, signals: FlixPickSignals)] = []
        var seen = Set<String>()
        let thread = latestPickThread(context)
        let sensitive = sensitivePaths(context)
        for item in context.items.prefix(scanned) {
            guard let path = item.path, item.link == nil, item.kind != .app, !context.sensitive.contains(item.id),
                  allowed(path, sensitive: sensitive, context: context), context.types.fits(item),
                  seen.insert(path).inserted else { continue }
            let pick = context.picks[path]
            let kind = FlixDragMemory.kindClass(of: item)
            var signals = FlixPickSignals(pickedCount: pick?.count ?? 0, lastPicked: pick?.last,
                                          dragCount: context.dropCounts[kind] ?? 0, dragKind: kind,
                                          activity: item.activity, date: max(item.date, pick?.last ?? .distantPast))
            if let thread, thread.memberIDs.contains(item.id), thread.pickedPath != path { signals.threadName = thread.name }
            candidates.append((item, signals))
        }
        // Files picked here that the history no longer lists (it keeps 5,000 rows, Spotlight may
        // not report every open).
        for (path, entry) in context.picks where !entry.isFolder && !seen.contains(path) {
            let ext = (path as NSString).pathExtension
            let type = UTType(filenameExtension: ext)
            guard context.types.fits(type: type, pathExtension: ext, isFolder: false),
                  allowed(path, sensitive: sensitive, context: context) else { continue }
            let item = FlixItem(path: path, name: (path as NSString).lastPathComponent,
                                kind: FlixItemKind.classify(contentType: type, isDirectory: false, isPackage: false,
                                                            isScreenshot: false),
                                activity: .opened, date: entry.last, contentTypeIdentifier: type?.identifier)
            candidates.append((item, FlixPickSignals(pickedCount: entry.count, lastPicked: entry.last, date: entry.last)))
        }
        return FlixPickRanker.rank(candidates, now: context.now, limit: limit).map { ranked in
            let item = ranked.id
            let parent = ((item.path ?? "") as NSString).deletingLastPathComponent
            return FlixPickRow(item: item, reason: reason(ranked.score.strongest, item: item, context: context),
                               location: breadcrumb(parent, home: context.home),
                               date: candidates.first { $0.id.id == item.id }?.signals.date ?? item.date)
        }
    }

    /// The Thread holding this app's most recent pick, so its other files read "Part of …".
    private static func latestPickThread(_ context: FlixPickContext) -> (name: String, memberIDs: Set<FlixItem.ID>, pickedPath: String)? {
        guard let latest = context.picks.filter({ !$0.value.isFolder }).max(by: { $0.value.last < $1.value.last }),
              let item = context.items.first(where: { $0.path == latest.key }),
              let thread = context.threads.first(where: { $0.memberIDs.contains(item.id) }) else { return nil }
        return (thread.name, Set(thread.memberIDs), latest.key)
    }

    // MARK: Save

    private static func folders(for context: FlixPickContext, limit: Int) -> [FlixPickRow] {
        var signals: [String: FlixPickSignals] = [:]
        var order: [String] = []
        let sensitive = sensitivePaths(context)
        func update(_ folder: String, _ change: (inout FlixPickSignals) -> Void) {
            let folder = FlixPaths.standardized(folder)
            guard isListableFolder(folder, home: context.home), allowed(folder, sensitive: sensitive, context: context)
            else { return }
            if signals[folder] == nil {
                signals[folder] = FlixPickSignals(date: .distantPast)
                order.append(folder)
            }
            change(&signals[folder]!)
        }
        for (path, entry) in context.picks where entry.isFolder {
            update(path) { signals in
                signals.pickedCount = entry.count
                signals.lastPicked = entry.last
                signals.date = max(signals.date, entry.last)
            }
        }
        let fitWindow = context.now.addingTimeInterval(-14 * 86_400)
        let savedWindow = context.now.addingTimeInterval(-3 * 86_400)
        for item in context.items.prefix(scanned) {
            guard let path = item.path, item.link == nil, item.kind != .app, !context.sensitive.contains(item.id),
                  !(context.hidesNoise && FlixNoiseRules.isNoise(path: path)) else { continue }
            if item.kind == .folder {
                update(path) { signals in
                    if signals.activity == nil { signals.activity = .opened }
                    signals.date = max(signals.date, item.date)
                }
                continue
            }
            let parent = (path as NSString).deletingLastPathComponent
            let fits = item.date >= fitWindow && !context.types.acceptsAnything && context.types.fits(item)
            let saved = item.date >= savedWindow && (item.activity == .saved || item.activity == .created)
            guard fits || saved else { continue }
            update(parent) { signals in
                if fits { signals.fittingFiles += 1 }
                if saved, signals.activity == nil || signals.activity == .opened { signals.activity = .saved }
                signals.date = max(signals.date, item.date)
            }
        }
        let candidates = order.compactMap { folder in signals[folder].map { (id: folder, signals: $0) } }
        return FlixPickRanker.rank(candidates, now: context.now, limit: limit).map { ranked in
            let folder = ranked.id
            let item = FlixItem(path: folder, name: folderName(folder, home: context.home), kind: .folder,
                                activity: .opened, date: signals[folder]?.date ?? context.now)
            return FlixPickRow(item: item, reason: reason(ranked.score.strongest, item: item, context: context),
                               location: breadcrumb((folder as NSString).deletingLastPathComponent, home: context.home),
                               date: item.date)
        }
    }

    /// Folders a Save picker can take that are worth suggesting: in the home folder (not inside
    /// Library, except iCloud Drive and cloud storage) or on another volume, never hidden, never a
    /// package such as an app or a photo library.
    static func isListableFolder(_ folder: String, home: String) -> Bool {
        let inHome = folder == home || folder.hasPrefix(home + "/")
        guard inHome || folder.hasPrefix("/Volumes/") else { return false }
        let library = home + "/Library"
        if folder == library || folder.hasPrefix(library + "/") {
            let iCloud = library + "/Mobile Documents"
            let cloud = library + "/CloudStorage"
            guard folder.hasPrefix(iCloud + "/") || folder.hasPrefix(cloud + "/") else { return false }
        }
        let components = folder.split(separator: "/")
        guard !components.contains(where: { $0.hasPrefix(".") }) else { return false }
        let ext = (folder as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext, conformingTo: .directory), type.conforms(to: .package) {
            return false
        }
        return true
    }

    // MARK: Text

    private static func reason(_ signal: FlixPickSignal, item: FlixItem, context: FlixPickContext) -> FlixPickReason {
        let save = context.kind == .save
        switch signal {
        case .picked(let count):
            return FlixPickReason(text: String(localized: save ? .flixPickReasonSavedHere(count) : .flixPickReasonPicked(count)),
                                  tone: .learned)
        case .thread(let name):
            return FlixPickReason(text: String(localized: .flixPickReasonThread(name)), tone: .context)
        case .new:
            let parent = ((item.path ?? "") as NSString).deletingLastPathComponent
            return FlixPickReason(text: String(localized: .flixPickReasonNew(folderName(parent, home: context.home))),
                                  tone: .new)
        case .dragged(let kind):
            return FlixPickReason(text: String(localized: .flixPickReasonSendsKind(FlixDragMemoryProvider.kindName(kind))),
                                  tone: .used)
        case .fittingFiles:
            return FlixPickReason(text: String(localized: .flixPickReasonFolderFits(context.appName)), tone: .used)
        case .used(let activity):
            if save {
                let text: LocalizedStringResource = activity == .opened ? .flixPickReasonOpened : .flixPickReasonFolderSaved
                return FlixPickReason(text: String(localized: text), tone: .used)
            }
            let text: LocalizedStringResource = switch activity {
            case .opened, .link: .flixPickReasonOpened
            case .saved: .flixPickReasonEdited
            case .downloaded: .flixPickReasonDownloaded
            case .created: .flixPickReasonAdded
            case .kept: .flixPickReasonKept
            }
            return FlixPickReason(text: String(localized: text), tone: .used)
        case .fits:
            return FlixPickReason(text: String(localized: .flixPickReasonFits(context.appName)), tone: .used)
        }
    }

    /// A folder's name, with iCloud Drive's container named as Finder names it.
    static func folderName(_ folder: String, home: String) -> String {
        if folder == home + "/Library/Mobile Documents/com~apple~CloudDocs" { return String(localized: .flixPickLocationICloud) }
        return FlixFolderNames.displayName(of: folder)
    }

    /// "Documents › Oak & Ash": the folder's last three places below the home folder, iCloud Drive,
    /// or the volume, from the path alone.
    static func breadcrumb(_ folder: String, home: String) -> String {
        let folder = FlixPaths.standardized(folder)
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        var names: [String] = []
        var current = folder
        while current != "/" && !current.isEmpty && names.count < 3 {
            // The home folder is named only for files right inside it.
            if current == home && !names.isEmpty { break }
            names.insert(folderName(current, home: home), at: 0)
            let parent = (current as NSString).deletingLastPathComponent
            if current == home || current == iCloud || parent == "/Volumes" { break }
            current = parent
        }
        return names.joined(separator: " › ")
    }
}

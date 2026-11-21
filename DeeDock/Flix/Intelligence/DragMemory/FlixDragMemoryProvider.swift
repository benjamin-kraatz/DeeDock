import Foundation

/// Drag memory and the Smart Filter tip, learned on this Mac only.
///
/// **Drops**: each drop out of the panel counts the dropped kinds ("pdf", "image") against the app
/// that was in front when the panel opened (macOS never says where a drop landed). Later, rows of
/// that kind say "↺ you've sent PDFs here before" while the same app is in front, and
/// ``likelyItem(for:among:)`` names the newest item of the kind usually sent there. After three
/// drops of one kind to one app, Flix Files says once that it noticed.
///
/// **Tip**: opens are counted by working folder and part of the day (morning, afternoon, evening).
/// A folder opened in the same part of the day on three different days of the last two weeks earns
/// one tip, "You open **Oak & Ash** files most mornings", offered once and never repeated.
///
/// Everything is counts in `memory.json` in Flix Files' Application Support folder; **Forget**
/// empties it. Only runs while `learnsDragDestinations` is on: `FlixIntelligence` asks nothing
/// otherwise, and ``observe(_:)`` checks it too. Main actor.
@MainActor
final class FlixDragMemoryProvider: FlixDragMemoryProviding {
    private let services: FlixSmartServices
    private(set) var memory = FlixDragMemory()
    private let file: FlixJSONFile<FlixDragMemory>?

    init(services: FlixSmartServices) {
        self.services = services
        file = services.storage.map { FlixJSONFile(url: $0.appending(path: "memory.json"), delay: .seconds(2)) }
        do { memory = try file?.load() ?? FlixDragMemory() } catch { file?.quarantine() }
    }

    func stop() { file?.flush() }

    /// Counts opens; called with the history on every annotation pass.
    func observe(_ items: [FlixItem]) {
        guard services.settings.learnsDragDestinations, memory.observeOpens(items) else { return }
        memory.prune(now: .now, keeping: Set(items.map(\.id.uuidString)))
        save()
    }

    func reason(for item: FlixItem, context: FlixFrontmostContext?) -> FlixDragReason? {
        guard let destination = Self.destination(context) else { return nil }
        let kind = FlixDragMemory.kindClass(of: item)
        guard memory.count(kind: kind, destination: destination) > 0 else { return nil }
        return FlixDragReason(text: "↺ " + String(localized: .flixDragReason(Self.kindName(kind))))
    }

    func recordDrop(of items: [FlixItem], context: FlixFrontmostContext?) -> String? {
        guard let destination = Self.destination(context), !items.isEmpty else { return nil }
        let noticed = memory.recordDrop(of: items, destination: destination, name: context?.applicationName)
        save()
        guard let kind = noticed.first else { return nil }
        let name = memory.destinationNames[destination] ?? context?.applicationName ?? destination
        return "✦ " + String(localized: .flixDragNoticed(Self.kindName(kind), name))
    }

    /// The newest item of the kind most often dropped on the app in front, for ranking the Fits
    /// card (phase B1's hook). Nil when nothing was learned for that app.
    func likelyItem(for context: FlixFrontmostContext?, among items: [FlixItem]) -> FlixItem.ID? {
        guard let destination = Self.destination(context), let kind = memory.usualKind(for: destination) else { return nil }
        return items.first { FlixDragMemory.kindClass(of: $0) == kind }?.id
    }

    func filterTip(items: [FlixItem], now: Date) -> FlixFilterTip? {
        observe(items)
        var excluded = FlixThreadClusterer.catchAllFolders()
        // A folder that already has a Smart Filter needs no tip.
        for filter in services.smartFilters {
            for rule in filter.rules {
                guard case .locationContains(let text) = rule else { continue }
                excluded.formUnion(memory.opens.keys.filter { ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(text) })
            }
        }
        guard let candidate = memory.tipCandidate(now: now, excluding: excluded) else { return nil }
        let id = FlixDragMemory.tipID(folder: candidate.folder, part: candidate.part)
        memory.offeredTips.insert(id)
        save()
        let name = FileManager.default.displayName(atPath: candidate.folder)
        let part = switch candidate.part {
        case .morning: String(localized: .flixTipPartMornings)
        case .afternoon: String(localized: .flixTipPartAfternoons)
        case .evening: String(localized: .flixTipPartEvenings)
        }
        return FlixFilterTip(id: id, message: String(localized: .flixTipMessage(name, part)),
                             proposal: FlixSmartFilter(name: name, emoji: "📁", rules: [.locationContains(name)]))
    }

    func forget() {
        memory = FlixDragMemory()
        save()
    }

    private func save() { file?.schedule(memory) }

    /// Where a drop is counted: the app in front, by bundle identifier.
    private static func destination(_ context: FlixFrontmostContext?) -> String? {
        context?.bundleIdentifier ?? context?.applicationName
    }

    private static func kindName(_ kind: String) -> String {
        switch kind {
        case "pdf": String(localized: .flixDragKindPDFs)
        case "image": String(localized: .flixDragKindPictures)
        case "spreadsheet": String(localized: .flixDragKindSpreadsheets)
        case "presentation": String(localized: .flixDragKindPresentations)
        case "document": String(localized: .flixDragKindDocuments)
        case "archive": String(localized: .flixDragKindArchives)
        case "folder": String(localized: .flixDragKindFolders)
        case "app": String(localized: .flixDragKindApps)
        case "link": String(localized: .flixDragKindLinks)
        default: String(localized: .flixDragKindFiles)
        }
    }
}

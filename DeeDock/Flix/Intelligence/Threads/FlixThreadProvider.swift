import Foundation

/// The sidebar's ✦ Threads: recent work grouped by meaning, names, folders, and time.
///
/// Each pass clusters the last ``window`` of activity (`FlixThreadClusterer`, off the main actor),
/// with Lookout's vectors when Lookout runs and by time, folder, and name words otherwise. A new
/// cluster keeps the identity, name, and summary of the previous thread it overlaps most (at least a
/// third of their members shared), so a thread stays selected and named while files join it; a new
/// thread is named after its oldest member, which keeps its identifier stable too. Threads are saved
/// in `threads.json`, so they survive a relaunch.
///
/// Names start as the fallback (shared folder or word) and are replaced by Apple Intelligence's name,
/// emoji, and summary in this provider's own worker, one thread at a time, never during a drag. A
/// thread is named again when fewer than ``renameBelow`` of its members are the ones it was named
/// for. The model sees member names, captions, and folders, never file contents, plus the names the
/// other threads already carry, so it tells them apart. Threads that still end up with the same name
/// are shown as one (``displayThreads(_:dates:)``).
///
/// A thread the person hides (``setHidden(_:thread:)``) stays hidden through later passes: a
/// cluster that keeps its identity keeps the flag, and a hidden thread no cluster matched is kept
/// while any of its members is still recent, so it cannot come back under a new identity on the
/// next pass. Main actor.
@MainActor
final class FlixThreadProvider: FlixThreadProviding {
    nonisolated struct Record: Codable, Equatable, Sendable {
        var id: String
        var memberIDs: [FlixItem.ID]
        var name: String
        var emoji: String
        var summary: String?
        var namedByModel = false
        /// The members Apple Intelligence saw when it named the thread.
        var namedMembers: [FlixItem.ID] = []
        /// The person hid the thread from the sidebar. Nil (not false) when shown, so older
        /// `threads.json` files decode.
        var hidden: Bool?
        /// The ``FlixThreadNamer/version`` of the instructions that named it; a thread named by an
        /// older version is named again once.
        var namingVersion: Int?
    }

    static let window: TimeInterval = 7 * 86_400
    static let renameBelow = 0.6

    private let services: FlixSmartServices
    private(set) var records: [Record] = []
    private let file: FlixJSONFile<[Record]>?
    private var queue: [String] = []
    private var worker: Task<Void, Never>?

    init(services: FlixSmartServices) {
        self.services = services
        file = services.storage.map { FlixJSONFile(url: $0.appending(path: "threads.json"), delay: .seconds(2)) }
        do { records = try file?.load() ?? [] } catch { file?.quarantine() }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        queue = []
        file?.flush()
    }

    func threads(for items: [FlixItem]) async -> [FlixThread] {
        guard services.settings.isEnabled, services.settings.groupsThreads else { return [] }
        let now = Date.now
        let catchAll = FlixThreadClusterer.catchAllFolders()
        let recent = items.filter { item in
            item.path != nil && item.kind != .app && item.kind != .link && now.timeIntervalSince(item.date) <= Self.window
                && !FlixNoiseRules.isNoise(path: item.path)
        }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dates = byID.mapValues(\.date)
        let vectors = await services.semantic.vectors(for: recent.compactMap(\.path))
        guard !Task.isCancelled else { return Self.displayThreads(records, dates: dates) }
        let entries = recent.map { item in
            FlixThreadClusterer.Entry(id: item.id, date: item.date, folder: Self.folder(of: item),
                                      words: FlixWords.distinctive(item.name), vector: item.path.flatMap { vectors[$0] })
        }
        let groups = await FlixThreadClusterer.cluster(entries, catchAll: catchAll)
        guard !Task.isCancelled else { return Self.displayThreads(records, dates: dates) }

        var taken = Set<String>()
        var next: [Record] = []
        for group in groups {
            let members = Set(group)
            let previous = records.filter { !taken.contains($0.id) }
                .map { ($0, Self.overlap(members, Set($0.memberIDs))) }
                .max { $0.1 < $1.1 }
            var record: Record
            if let previous, previous.1 >= 1.0 / 3.0 {
                record = previous.0
            } else {
                let oldest = group.compactMap { byID[$0] }.min { $0.firstSeen < $1.firstSeen }
                record = Record(id: "thread-" + (oldest?.id ?? group[0]).uuidString, memberIDs: group, name: "", emoji: "")
            }
            record.memberIDs = group
            if !record.namedByModel {
                let named = namerMembers(group, byID: byID)
                record.name = FlixThreadNamer.fallbackName(named, catchAll: catchAll)
                record.emoji = FlixThreadNamer.fallbackEmoji(named)
            }
            taken.insert(record.id)
            next.append(record)
        }
        let recentIDs = Set(recent.map(\.id))
        next += records.filter { $0.hidden == true && !taken.contains($0.id) && $0.memberIDs.contains(where: recentIDs.contains) }
        if next != records {
            records = next
            file?.schedule(records)
        }
        enqueueNaming()
        return Self.displayThreads(records, dates: dates)
    }

    // MARK: Naming

    private func needsName(_ record: Record) -> Bool {
        guard record.hidden != true else { return false }
        return !record.namedByModel || record.namingVersion != FlixThreadNamer.version
            || Self.overlap(Set(record.memberIDs), Set(record.namedMembers)) < Self.renameBelow
    }

    private func enqueueNaming() {
        guard FlixLanguageModel.isAvailable else { return }
        let waiting = Set(queue)
        queue += records.filter { needsName($0) && !waiting.contains($0.id) }.map(\.id)
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            await self?.drainNaming()
            self?.worker = nil
        }
    }

    private func drainNaming() async {
        var named = false
        while !Task.isCancelled, !queue.isEmpty {
            let id = queue.removeFirst()
            await services.waitWhileDragging()
            guard !Task.isCancelled, services.settings.isEnabled else { break }
            guard services.settings.groupsThreads,
                  let record = records.first(where: { $0.id == id }), needsName(record) else { continue }
            let byID = Dictionary(services.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let members = record.memberIDs
            let otherNames = records.filter { $0.id != id && $0.hidden != true && !$0.name.isEmpty }.map(\.name)
            guard let generated = await FlixThreadNamer.generated(for: namerMembers(members, byID: byID),
                                                                  otherNames: otherNames),
                  !Task.isCancelled, let index = records.firstIndex(where: { $0.id == id }) else { continue }
            records[index].name = generated.name
            records[index].emoji = generated.emoji
            records[index].summary = generated.summary.isEmpty ? nil : generated.summary
            records[index].namedByModel = true
            records[index].namedMembers = members
            records[index].namingVersion = FlixThreadNamer.version
            named = true
        }
        if named, !Task.isCancelled {
            file?.schedule(records)
            services.requestRefresh()
        }
    }

    private func namerMembers(_ ids: [FlixItem.ID], byID: [FlixItem.ID: FlixItem]) -> [FlixThreadNamer.Member] {
        ids.compactMap { byID[$0] }.map { item in
            FlixThreadNamer.Member(name: item.name, caption: item.path.flatMap { services.analyses[$0]?.caption },
                                   folder: Self.folder(of: item), kind: item.kind, activity: item.activity)
        }
    }

    // MARK: Hiding

    /// Hides a thread from the sidebar, or shows it again, and returns the threads as shown now.
    /// Records shown as one with it (the same name) change with it.
    func setHidden(_ hidden: Bool, thread id: String) -> [FlixThread] {
        if let key = records.first(where: { $0.id == id }).map({ Self.nameKey($0.name) }) {
            for index in records.indices where records[index].id == id || (!key.isEmpty && Self.nameKey(records[index].name) == key) {
                records[index].hidden = hidden ? true : nil
            }
            file?.schedule(records)
        }
        let dates = Dictionary(services.items.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })
        return Self.displayThreads(records, dates: dates)
    }

    // MARK: Helpers

    private static func folder(of item: FlixItem) -> String? {
        guard let path = item.path else { return nil }
        return item.kind == .folder ? path : (path as NSString).deletingLastPathComponent
    }

    /// Shared members over all members (Jaccard).
    static func overlap(_ a: Set<FlixItem.ID>, _ b: Set<FlixItem.ID>) -> Double {
        let union = a.union(b).count
        return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
    }

    /// The threads as the sidebar and the morning card see them: hidden records left out, and records
    /// with the same name (ignoring case, accents, and surrounding spaces) shown as one thread.
    ///
    /// The clusterer can split one piece of work in two (files more than ``FlixThreadClusterer/linkWindow``
    /// apart, or in two folders), and each part may then be named the same. Two rows reading "Craft
    /// Anything" say nothing the person can choose between, so they become one. The newest record
    /// (records are kept newest first) gives the merged thread its identity, name, emoji, and summary,
    /// so a selected thread stays selected. Members are joined, newest first by `dates` (unknown
    /// dates last, in record order), and capped at ``FlixThreadClusterer/memberLimit``.
    static func displayThreads(_ records: [Record], dates: [FlixItem.ID: Date]) -> [FlixThread] {
        var threads: [FlixThread] = []
        var indexByName: [String: Int] = [:]
        for record in records where record.hidden != true {
            let key = nameKey(record.name)
            guard !key.isEmpty, let index = indexByName[key] else {
                if !key.isEmpty { indexByName[key] = threads.count }
                threads.append(thread(record))
                continue
            }
            let known = Set(threads[index].memberIDs)
            threads[index].memberIDs += record.memberIDs.filter { !known.contains($0) }
            threads[index].namedByAppleIntelligence = threads[index].namedByAppleIntelligence || record.namedByModel
        }
        for index in threads.indices {
            let order = Dictionary(threads[index].memberIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            let sorted = threads[index].memberIDs.sorted { a, b in
                switch (dates[a], dates[b]) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return order[a, default: 0] < order[b, default: 0]
                }
            }
            threads[index].memberIDs = Array(sorted.prefix(FlixThreadClusterer.memberLimit))
        }
        return threads
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func thread(_ record: Record) -> FlixThread {
        FlixThread(id: record.id, name: record.name, emoji: record.emoji, summary: record.summary,
                   memberIDs: record.memberIDs, namedByAppleIntelligence: record.namedByModel)
    }
}

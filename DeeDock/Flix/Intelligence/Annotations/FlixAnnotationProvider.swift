import Foundation

/// Phase B2's annotations: captions and better names for cryptic files, key facts, folder
/// suggestions for downloads, and version families. Sensitive flags are left as they are (phase
/// B1's guard), so this provider never clears one.
///
/// Each history pass (`FlixIntelligence.historyChanged`, coalesced to one every two seconds) is
/// quick: it groups versions by name, ranks folders by Lookout vectors or rules, and reads cached
/// analyses. Reading files and asking Apple Intelligence happen in this provider's own worker, one
/// file at a time, newest first, at most ``queueLimit`` waiting. The worker pauses while a drag is
/// in progress, caches each result by path and stamp (`FlixAnalysisStore`), and asks for a new pass
/// after every few files, which then shows them.
///
/// Respects the settings on every pass: nothing at all while Flix Files is off, captions, names, and
/// facts only with `writesCaptions`, folder suggestions only with `suggestsFolders`. Reads only what `FlixReadPolicy` allows, so it never
/// makes macOS ask for a folder. ``stop()`` cancels the worker. Main actor.
@MainActor
final class FlixAnnotationProvider: FlixAnnotationProviding {
    /// The newest items considered for reading and stamps each pass.
    static let consideredItems = 400
    /// The most files waiting to be read.
    static let queueLimit = 40
    /// A model call that failed is tried again after this long.
    static let retryAfter: TimeInterval = 86_400

    private let services: FlixSmartServices
    private var queue: [FlixItem.ID] = []
    private var worker: Task<Void, Never>?
    /// Each item's path at the last pass, so an analysis follows a rename or move made in Flix Files.
    private var lastPaths: [FlixItem.ID: String] = [:]
    /// Apple Intelligence read a document at this path: the sensitive guard settles its verdict.
    var documentRead: ((String) -> Void)?

    init(services: FlixSmartServices) {
        self.services = services
    }

    func stop() {
        worker?.cancel()
        worker = nil
        queue = []
    }

    func annotations(for items: [FlixItem], known: [FlixItem.ID: FlixItemAnnotation]) async
        -> [FlixItem.ID: FlixItemAnnotation] {
        guard services.settings.isEnabled else {
            stop()
            return [:]
        }
        services.observeActivity(items)
        followRenames(items)
        let settings = services.settings
        let policy = services.readPolicy
        let files = items.filter { $0.path != nil && $0.kind != .app && $0.kind != .link }
        let recent = Array(files.prefix(Self.consideredItems))

        // Lookout's vectors confirm version families and place downloads; without Lookout both fall
        // back to names and rules.
        let vectorPaths = Array(files.prefix(1_500)).compactMap(\.path)
        let vectors = await services.semantic.vectors(for: vectorPaths)
        guard !Task.isCancelled else { return [:] }
        let versions = FlixVersionFamilies.groups(recent.filter { $0.kind != .folder }.map {
            FlixVersionFamilies.Member(id: $0.id, name: $0.name, kind: $0.kind, date: $0.date,
                                       vector: $0.path.flatMap { vectors[$0] })
        })
        let downloads = FlixPaths.downloads()
        let candidates = settings.suggestsFolders
            ? FlixFolderSuggester.candidates(files.prefix(1_500).compactMap { item in
                item.path.map { (path: $0, vector: vectors[$0]) }
            }, excluded: [downloads, FlixPaths.standardized(NSHomeDirectory() + "/Desktop"),
                          FlixPaths.standardized(NSHomeDirectory())])
            : []

        let readable = recent.compactMap(\.path).filter(policy.canRead)
        let stamps = await FlixContentReader.stamps(readable, policy: policy)
        guard !Task.isCancelled else { return [:] }

        var result: [FlixItem.ID: FlixItemAnnotation] = [:]
        let empty = FlixItemAnnotation()
        for item in items {
            var annotation = FlixItemAnnotation()
            if let placement = versions[item.id] {
                annotation.versionGroup = placement.group
                annotation.versionRank = placement.rank
            }
            let path = item.path
            // A record whose file changed since is stale; items too old to be stamped keep theirs.
            var record = path.flatMap { services.analyses[$0] }
            if let current = path.flatMap({ stamps[$0] }), record?.stamp != current { record = nil }
            if settings.writesCaptions, let record {
                let cryptic = FlixFileNaming.isCryptic(item.name)
                annotation.caption = cryptic ? record.caption : nil
                annotation.renameSuggestion = cryptic && record.suggestedName != item.name ? record.suggestedName : nil
                annotation.facts = record.facts.map(Self.fact)
            }
            if settings.suggestsFolders, let path, item.kind != .folder, (path as NSString).deletingLastPathComponent == downloads {
                let subject = FlixFolderSuggester.Subject(name: item.name, caption: record?.caption, kind: item.kind,
                                                          vector: vectors[path])
                annotation.folderSuggestion = FlixFolderSuggester.suggestion(for: subject, among: candidates)
            }
            if let old = known[item.id] {
                annotation.isSensitive = old.isSensitive
                annotation.sensitiveReason = old.sensitiveReason
                annotation.isNoise = old.isNoise
            }
            if annotation != (known[item.id] ?? empty) { result[item.id] = annotation }
        }

        if settings.writesCaptions {
            enqueue(recent.filter { item in
                guard let path = item.path, let stamp = stamps[path] else { return false }
                return needsAnalysis(item, record: services.analyses[path], stamp: stamp)
            })
        } else {
            stop()
        }
        services.analyses.prune(keeping: Set(items.compactMap(\.path)))
        return result
    }

    // MARK: Reading in the background

    private func needsAnalysis(_ item: FlixItem, record: FlixAnalysisRecord?, stamp: FlixFileStamp) -> Bool {
        guard let record, record.stamp == stamp else { return true }
        guard Self.wantsModel(item), FlixLanguageModel.isAvailable else { return false }
        if record.modelFailed { return Date.now.timeIntervalSince(record.analyzedAt) > Self.retryAfter }
        return !record.modelConsidered
    }

    /// Files Apple Intelligence reads: cryptic names (for a caption) and documents a person reads
    /// (for their kind and facts).
    private static func wantsModel(_ item: FlixItem) -> Bool {
        FlixFileNaming.isCryptic(item.name)
            || (item.kind == .document && FlixFactExtractor.readsFacts(contentType: item.contentTypeIdentifier, name: item.name))
    }

    private func enqueue(_ items: [FlixItem]) {
        let waiting = Set(queue)
        // Newest first: what just arrived is what the person looks at.
        queue = (items.map(\.id).filter { !waiting.contains($0) } + queue).prefix(Self.queueLimit).map { $0 }
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    private func drain() async {
        var unshown = 0
        while !Task.isCancelled, !queue.isEmpty {
            let id = queue.removeFirst()
            await services.waitWhileDragging()
            guard !Task.isCancelled else { break }
            // Re-checked per file: switching Flix Files or captions off stops the worker at once.
            guard services.settings.isEnabled else { break }
            // Spelling only on the main actor; `stamps` resolves the path off it and skips what the
            // policy refuses, so an unreadable file is never analyzed.
            guard services.settings.writesCaptions, let item = services.item(id), let path = item.path,
                  services.readPolicy.spellingIsReadable(path),
                  let stamp = await FlixContentReader.stamps([path], policy: services.readPolicy)[path] else { continue }
            guard needsAnalysis(item, record: services.analyses[path], stamp: stamp) else {
                // Read meanwhile (an earlier pass queued it twice): the cached analysis stands.
                Analytics.count(.aiCacheHits)
                continue
            }
            let analyzed = await FlixFileAnalyzer.analyze(item, stamp: stamp, useModel: FlixLanguageModel.isAvailable,
                                                          policy: services.readPolicy)
            guard !Task.isCancelled else { break }
            if analyzed?.caption != nil { Analytics.count(.captionsGenerated) }
            // A file that couldn't be read gets an empty record, so it isn't read again until it changes.
            services.analyses.set(analyzed ?? FlixAnalysisRecord(stamp: stamp, analyzedAt: .now), for: path)
            if analyzed?.documentKind != nil { documentRead?(path) }
            unshown += 1
            if unshown >= 4 {
                services.requestRefresh()
                unshown = 0
            }
        }
        if unshown > 0, !Task.isCancelled { services.requestRefresh() }
    }

    /// Moves cached analyses along with items Flix Files renamed or moved.
    private func followRenames(_ items: [FlixItem]) {
        var paths: [FlixItem.ID: String] = [:]
        for item in items {
            guard let path = item.path else { continue }
            paths[item.id] = path
            if let old = lastPaths[item.id], old != path {
                services.analyses.move(from: old, to: path, newName: item.name)
            }
        }
        lastPaths = paths
    }

    // MARK: Chips

    /// The chip a fact draws, in the person's language.
    static func fact(_ value: FlixFactValue) -> FlixFact {
        switch value {
        case .due(let date):
            FlixFact(text: String(localized: .flixFactDue(date.formatted(.dateTime.month(.abbreviated).day()))), style: .due,
                     help: String(localized: .flixFactHelpDue))
        case .validUntil(let date):
            FlixFact(text: String(localized: .flixFactValidUntil(date.formatted(.dateTime.month(.abbreviated).day()))),
                     style: .due, help: String(localized: .flixFactHelpValidUntil))
        case .amount(let value, let currency):
            // Whole amounts without cents ("€1,240"), others with both digits ("14,90 €", not "14,9 €").
            FlixFact(text: value.formatted(.currency(code: currency)
                         .precision(.fractionLength(value.rounded() == value ? 0...0 : 2...2))), style: .money,
                     help: String(localized: .flixFactHelpAmount))
        case .pages(let count): FlixFact(text: String(localized: .flixFactPages(count)), help: String(localized: .flixFactHelpPages))
        case .slides(let count):
            FlixFact(text: String(localized: .flixFactSlides(count)), help: String(localized: .flixFactHelpSlides))
        case .needsSignature:
            FlixFact(text: String(localized: .flixFactNeedsSignature), style: .signature,
                     help: String(localized: .flixFactHelpNeedsSignature))
        case .signed: FlixFact(text: String(localized: .flixFactSigned), style: .money, help: String(localized: .flixFactHelpSigned))
        case .paid: FlixFact(text: String(localized: .flixFactPaid), help: String(localized: .flixFactHelpPaid))
        case .autoDebit: FlixFact(text: String(localized: .flixFactAutoDebit), help: String(localized: .flixFactHelpAutoDebit))
        }
    }
}

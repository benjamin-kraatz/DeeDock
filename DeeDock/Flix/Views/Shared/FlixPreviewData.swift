#if DEBUG
import Foundation

/// Deterministic sample data for Flix Files previews, after the mockup's scene. Paths sit under a
/// made-up home folder that the preview read policy refuses, so previews draw type icons and never
/// touch the disk.
@MainActor
enum FlixPreviewData {
    /// Friday 20 November 2026, 21:20.
    static let now: Date = {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 11, 20, 21, 20)
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }()

    static let home = "/Users/preview"
    static let policy = FlixReadPolicy(home: home, allowedRoots: [])

    private static func item(_ index: Int, _ name: String, _ folder: String, _ kind: FlixItemKind, _ activity: FlixActivity,
                             minutes: Double, type: String, from host: String? = nil, flagged: Bool = false) -> FlixItem {
        FlixItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                 path: home + "/" + folder + "/" + name, name: name, kind: kind, activity: activity,
                 date: now.addingTimeInterval(-minutes * 60),
                 sourcePage: host.map { URL(string: "https://\($0)/")! }, contentTypeIdentifier: type,
                 isFlagged: flagged)
    }

    static let items: [FlixItem] = [
        item(1, "Screenshot 2026-11-20 at 21.18.png", "Desktop", .screenshot, .created, minutes: 2, type: "public.png"),
        item(2, "Invoice-2026-11.pdf", "Downloads", .document, .downloaded, minutes: 6, type: "com.adobe.pdf",
             from: "billing.example.com"),
        item(3, "Signed contract.pdf", "Downloads", .document, .downloaded, minutes: 9, type: "com.adobe.pdf",
             from: "sign.example.com"),
        item(4, "document (3).pdf", "Downloads", .document, .downloaded, minutes: 12, type: "com.adobe.pdf",
             from: "files.example.com"),
        item(5, "Launch deck.key", "Library/Mobile Documents/com~apple~CloudDocs/Talks", .document, .saved, minutes: 14,
             type: "com.apple.iwork.keynote.sffkey"),
        item(6, "Passport scan.jpg", "Documents/Personal", .image, .created, minutes: 18, type: "public.jpeg"),
        item(7, "Oak & Ash", "Documents/Clients", .folder, .opened, minutes: 33, type: "public.folder"),
        item(8, "FlixPanelController.swift", "Projects/DeeDock/Flix", .document, .saved, minutes: 63,
             type: "public.swift-source"),
        item(9, "Budget 2027.numbers", "Documents/Finance", .document, .opened, minutes: 128,
             type: "com.apple.iwork.numbers.sffnumbers"),
        item(10, "IMG_4821.HEIC", "Pictures/Berlin trip", .image, .opened, minutes: 1_530, type: "public.heic"),
        item(11, "Contract draft v3.docx", "Downloads", .document, .downloaded, minutes: 1_640,
             type: "org.openxmlformats.wordprocessingml.document", from: "docs.example.com"),
        item(12, "Lease agreement.pdf", "Documents/Home", .document, .opened, minutes: 29_500, type: "com.adobe.pdf",
             flagged: true),
        item(13, "Budget 2027.numbers.sb-2f1a", "Documents/Finance", .other, .saved, minutes: 3, type: "public.data"),
    ]

    static let annotations: [FlixItem.ID: FlixItemAnnotation] = [
        items[0].id: FlixItemAnnotation(caption: "Xcode build error: missing module FlixKit",
                                        renameSuggestion: "Xcode build error – FlixKit.png"),
        items[1].id: FlixItemAnnotation(facts: [FlixFact(text: "Due Dec 4", style: .due), FlixFact(text: "€1,240", style: .money)],
                                        folderSuggestion: home + "/Documents/Finance"),
        items[2].id: FlixItemAnnotation(facts: [FlixFact(text: "Signed", style: .money)], versionGroup: "contract",
                                        versionRank: 3),
        items[3].id: FlixItemAnnotation(caption: "Oak & Ash packaging quote, 3 options",
                                        renameSuggestion: "Oak & Ash – Packaging quote.pdf",
                                        facts: [FlixFact(text: "€3,980", style: .money)]),
        items[5].id: FlixItemAnnotation(caption: "Passport photo page", isSensitive: true),
        items[10].id: FlixItemAnnotation(facts: [FlixFact(text: "Needs signature", style: .signature)],
                                         versionGroup: "contract", versionRank: 2),
    ]

    static let threads: [FlixThread] = [
        FlixThread(id: "oak", name: "Oak & Ash packaging", emoji: "🌳",
                   summary: "Contract signed today. The quote is ready for review; v3 of the draft still asked for a signature.",
                   memberIDs: [items[2].id, items[3].id, items[6].id, items[10].id], namedByAppleIntelligence: true),
        FlixThread(id: "finance", name: "Monthly bills", emoji: "🧾", summary: "November invoice is due Dec 4.",
                   memberIDs: [items[1].id, items[8].id]),
    ]

    static let smartFilters = [FlixSmartFilter(name: "Invoices", emoji: "🧾", rules: [.nameContains("invoice")])]
    static let favorites = [
        FlixFavorite(kind: .folder, path: home + "/Documents/Clients", name: "Clients"),
        FlixFavorite(kind: .folder, path: home + "/Documents/Finance", name: "Finance"),
        FlixFavorite(kind: .app, path: "/System/Applications/Preview.app", name: "Preview"),
    ]

    static let fits = FlixFitsResult(windowLabel: "portal.example.com",
                                     chain: FlixReaderChain(steps: [.accessibility], succeeded: true),
                                     fits: [FlixFit(itemID: items[2].id, phrase: "the signed contract"),
                                            FlixFit(itemID: items[1].id, phrase: "this month's invoice",
                                                    memory: FlixDragReason(text: "you've sent PDFs here before"))])

    /// A deliberately long name, for truncation and German layouts.
    static let longItem = item(14, "Abschlussbericht Verpackungskonzept Oak & Ash – finale Fassung nach Kundenfeedback (Kopie 2).pdf",
                               "Downloads", .document, .downloaded, minutes: 4, type: "com.adobe.pdf",
                               from: "kundenportal.verpackungsdienstleister.example.com")

    static let link = FlixItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
                               link: FlixLink(url: URL(string: "https://docs.example.com/d/packaging-brief")!,
                                              title: "Q4 packaging brief"),
                               name: "Q4 packaging brief", kind: .link, activity: .link,
                               date: now.addingTimeInterval(-25 * 60))

    static let morning = FlixMorningCard(
        message: "Yesterday you were on **Berlin trip photos** (2 photos, not sorted yet) and the **Oak & Ash contract**: v3 still asked for a signature.",
        actions: [.init(label: "Reopen Oak & Ash", target: .open([]), isPrimary: true),
                  .init(label: "Berlin photos", target: .filter(.all))])

    static let tidy = [FlixTidySuggestion(itemID: items[3].id, rename: "Oak & Ash – Packaging quote.pdf",
                                          moveTo: home + "/Documents/Clients"),
                       FlixTidySuggestion(itemID: items[1].id, moveTo: home + "/Documents/Finance"),
                       FlixTidySuggestion(itemID: items[0].id, rename: "Xcode build error – FlixKit.png")]

    static let tokens = [FlixQueryToken(label: "Downloaded", rule: .activity(.downloaded)),
                         FlixQueryToken(label: "PDFs", rule: .fileExtension("pdf")),
                         FlixQueryToken(label: "Last 7 days", rule: .withinDays(7))]

    static let proposal = FlixSmartFilterProposal(
        filter: FlixSmartFilter(name: "Oak & Ash", emoji: "🌳", rules: [.locationContains("Oak & Ash")]),
        ruleDescriptions: ["Location contains `Oak & Ash`", "or about `Oak & Ash packaging` by meaning"],
        generatedByModel: true)

    /// A state of the panel worth looking at.
    enum Scenario {
        case stream, intelligence
        /// The Fits card still reading the window, under the morning card.
        case fitsLoading
        case thread
        /// Search with example sentences, nothing typed.
        case search
        case understanding, tokens
        case moreLikeThis
        case empty, nothingMatches
        /// Long names and a link row, for truncation and German.
        case longNames
        case tidySheet, smartFilterSheet, smartFilterProposal, renameSheet
        case askRobi, askRobiAnswering, askRobiFailed
        case sensitiveQuestion, newerVersionQuestion
    }

    /// A panel state over an in-memory history. Providers, where a scenario needs them, are stubs
    /// that answer from this file.
    static func panelState(_ scenario: Scenario) -> FlixPanelState {
        var document = FlixHistoryDocument()
        switch scenario {
        case .empty: document.items = []
        case .longNames: document.items = [items[0], longItem, link] + items.dropFirst()
        default: document.items = items
        }
        let history = FlixHistory(folder: nil, document: document,
                                  library: FlixLibraryDocument(favorites: favorites, smartFilters: smartFilters))
        let intelligence = FlixIntelligence()
        let state = FlixPanelState(history: history, intelligence: intelligence,
                                   settingsStore: FlixSettingsStore(repository: nil))
        state.readPolicy = policy
        state.now = now
        state.phase = .shown

        let tip = FlixFilterTip(id: "oak", message: "You open Oak & Ash files most mornings. Make a Smart Filter for them?",
                                proposal: proposal.filter)
        if scenario != .stream, scenario != .empty {
            var providers = FlixIntelligenceProviders()
            let stub = FlixPreviewProvider()
            (providers.search, providers.tidy, providers.smartFilters, providers.robi, providers.similarity) =
                (stub, stub, stub, stub, stub)
            if scenario == .askRobiFailed { stub.answersOnDevice = true }
            stub.understandingForever = scenario == .understanding
            intelligence.providers = providers
        }
        switch scenario {
        case .stream, .empty:
            break
        case .fitsLoading:
            intelligence.applyPreview(fits: .reading(windowLabel: "portal.example.com",
                                                     chain: FlixReaderChain(steps: [.accessibility, .vision])),
                                      threads: threads, annotations: annotations, morning: morning)
        case .understanding:
            intelligence.applyPreview(threads: threads, annotations: annotations, query: .understanding)
        case .tokens:
            intelligence.applyPreview(threads: threads, annotations: annotations,
                                      query: .understood(tokens: tokens, matches: [items[1].id: .name, items[2].id: .name,
                                                                                   items[3].id: .meaning]))
        case .moreLikeThis:
            intelligence.applyPreview(threads: threads, annotations: annotations,
                                      moreLikeThis: FlixMoreLikeThis(sourceID: items[9].id,
                                                                     resultIDs: [items[0].id, items[5].id]))
        case .smartFilterProposal:
            intelligence.applyPreview(threads: threads, annotations: annotations, smartFilterDraft: .ready(proposal))
        case .askRobiAnswering:
            intelligence.applyPreview(threads: threads, annotations: annotations,
                                      robi: .answering(question: "What's the total?",
                                                       text: "Together they come to **€2,480**. November's €1,240 is due"))
        case .askRobiFailed:
            intelligence.applyPreview(threads: threads, annotations: annotations,
                                      robi: .failed(question: "Summarize", message: "Robi couldn't read these files."))
        default:
            intelligence.applyPreview(fits: .ready(fits), threads: threads, annotations: annotations, tidy: tidy,
                                      filterTip: tip)
        }

        switch scenario {
        case .thread: state.filter = .thread("oak")
        case .nothingMatches: state.history.setFlagged(false, for: [items[11].id]); state.filter = .activity(.flagged)
        case .search: state.searchActive = true
        case .understanding, .tokens:
            state.searchActive = true
            state.searchText = "PDFs I downloaded last week"
            // Typing clears the query; put the scenario's back.
            intelligence.applyPreview(threads: threads, annotations: annotations,
                                      query: scenario == .tokens
                                          ? .understood(tokens: tokens, matches: [items[1].id: .name, items[2].id: .name,
                                                                                  items[3].id: .meaning])
                                          : .understanding)
        case .tidySheet: state.sheet = .tidy
        case .smartFilterSheet, .smartFilterProposal: state.sheet = .smartFilter
        case .renameSheet: state.sheet = .rename(items[3].id)
        case .askRobi, .askRobiAnswering, .askRobiFailed: state.sheet = .askRobi([items[1].id, items[2].id])
        case .sensitiveQuestion:
            state.confirmation = FlixPendingConfirmation(
                confirmation: .sensitive(itemID: items[5].id, reason: nil, destination: "Safari"), itemIDs: [items[5].id])
        case .newerVersionQuestion:
            state.confirmation = FlixPendingConfirmation(
                confirmation: .newerVersion(itemID: items[10].id, newerID: items[2].id), itemIDs: [items[10].id])
            state.showToast("Moved “Invoice-2026-11.pdf” to Finance.", undo: {})
        default: break
        }
        if let first = state.navigationOrder.first {
            state.selection = [first]
            state.cursor = first
        }
        return state
    }

    /// The plain stream, or the stream with every intelligence slot filled.
    static func panelState(withIntelligence: Bool = false) -> FlixPanelState {
        panelState(withIntelligence ? .intelligence : .stream)
    }
}

/// Answers every provider question from fixed values, at once, without touching anything.
@MainActor
private final class FlixPreviewProvider: FlixSearchProviding, FlixTidyProviding, FlixSmartFilterGenerating,
                                         FlixRobiProviding, FlixSimilarityProviding {
    let examples = ["contract Mike sent last week", "screenshot with the build error", "photos from Berlin",
                    "invoices over €1,000"]
    var lastReport: FlixSearchReport? { nil }
    let isReady = true
    var answersOnDevice = false

    /// Typing in a preview runs the search like the app does, so the scenario's answer comes back
    /// from here: the tokens, or nothing for as long as the preview lives ("Understanding…").
    var understandingForever = false

    func understand(_ text: String, items: [FlixItem], now: Date) async
        -> (tokens: [FlixQueryToken], matches: [FlixItem.ID: FlixMatchKind]?)? {
        if understandingForever {
            try? await Task.sleep(for: .seconds(3_600))
            return nil
        }
        let items = FlixPreviewData.items
        return (FlixPreviewData.tokens, [items[1].id: .name, items[2].id: .name, items[3].id: .meaning])
    }
    func suggestions(for items: [FlixItem], annotations: [FlixItem.ID: FlixItemAnnotation]) async
        -> [FlixTidySuggestion] { FlixPreviewData.tidy }
    func proposal(for sentence: String, items: [FlixItem]) async -> FlixSmartFilterProposal? { FlixPreviewData.proposal }
    func questions(for items: [FlixItem]) -> [String] {
        ["What's the total?", "When is each one due?", "Draft a message that mentions them"]
    }
    func answer(_ question: String, about items: [FlixItem]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func similar(to item: FlixItem, in items: [FlixItem]) async -> [FlixItem.ID] { [] }
    func cachedMatch(topic: String, item: FlixItem) -> Bool? { nil }
}
#endif

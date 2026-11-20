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

    /// A panel state over an in-memory history, with no providers.
    static func panelState(withIntelligence: Bool = false) -> FlixPanelState {
        var document = FlixHistoryDocument()
        document.items = items
        let history = FlixHistory(folder: nil, document: document,
                                  library: FlixLibraryDocument(favorites: favorites, smartFilters: smartFilters))
        let intelligence = FlixIntelligence()
        if withIntelligence {
            intelligence.applyPreview(fits: .ready(fits), threads: threads, annotations: annotations)
        }
        let state = FlixPanelState(history: history, intelligence: intelligence,
                                   settingsStore: FlixSettingsStore(repository: nil))
        state.readPolicy = policy
        state.now = now
        state.phase = .shown
        state.selection = [items[0].id]
        state.cursor = items[0].id
        return state
    }
}
#endif

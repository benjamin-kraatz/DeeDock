import Foundation
import FoundationModels

/// `LookoutBench corpus`: writes an eval corpus of everyday documents with Apple's on-device model, mostly German,
/// some English: invoices, contracts, letters, notes, recipes, plans, as PDFs, scanned PDFs, Word, RTF, text and
/// Markdown files, and screenshots of them.
///
/// The corpus is the realistic filler around the real folders: documents that look alike (many invoices, many
/// letters) so a query has to find the right one, in folders named the way people name them, with file dates the
/// contents agree with. Each document's spec (type, topic, language, format, name style, date) comes from a seeded
/// generator, so a rerun writes the same set; a document whose file exists is skipped, so a stopped run resumes.
enum CorpusCommand {
    static func run(out: URL, count: Int, seed: UInt64) async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw BenchFailure("Apple's on-device model isn't available: \(SystemLanguageModel.default.availability)")
        }
        var random = SeededRandom(seed: seed)
        let specs = (0..<count).map { CorpusSpec.make(number: $0, random: &random) }
        let todo = specs.filter { !FileManager.default.fileExists(atPath: $0.url(in: out).path) }
        print("\(specs.count) documents, \(specs.count - todo.count) already written; writing \(todo.count) to \(out.path)")

        var written = 0, failed = 0
        let start = Date()
        for (number, spec) in todo.enumerated() {
            do {
                let document = try await write(spec)
                let url = spec.url(in: out)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try CorpusRenderer.render(document, as: spec.format, to: url)
                try FileManager.default.setAttributes([.modificationDate: spec.date, .creationDate: spec.date],
                                                      ofItemAtPath: url.path)
                written += 1
            } catch {
                failed += 1
                print("  skipped \(spec.topic): \(error)")
            }
            if (number + 1) % 10 == 0 {
                print(String(format: "  %d/%d, %.1f s a document", number + 1, todo.count,
                             Date().timeIntervalSince(start) / Double(number + 1)))
            }
        }
        print("wrote \(written) documents; \(failed) refused or failed")
    }

    @Generable
    struct Document {
        @Guide(description: "The document's heading, as it would be printed on it.")
        var title: String
        @Guide(description: "The document's full text, 120 to 350 words, with concrete invented details: names, addresses, dates, amounts, customer or order numbers.")
        var text: String
    }

    private static func write(_ spec: CorpusSpec) async throws -> CorpusDocument {
        let instructions = spec.german
            ? "Du schreibst realistische deutsche Alltagsdokumente mit erfundenen, aber plausiblen Details: Namen, Adressen, Daten, Beträge in Euro, Kunden-, Vertrags- und Rechnungsnummern. Schreibe nur auf Deutsch."
            : "You write realistic everyday documents with invented but plausible details: names, addresses, dates, amounts, customer, contract and invoice numbers. Write in English."
        let session = LanguageModelSession(instructions: instructions)
        let date = ISO8601DateFormatter.day.string(from: spec.date)
        let prompt = spec.german
            ? "Schreibe: \(spec.topic). Das Dokument ist vom \(date)."
            : "Write: \(spec.topic). The document is dated \(date)."
        let response = try await session.respond(to: prompt, generating: Document.self)
        return CorpusDocument(title: response.content.title, text: response.content.text)
    }
}

/// One document to write: what it is, and how it's stored.
struct CorpusSpec {
    enum Format: String, CaseIterable {
        case pdf, scan, docx, rtf, txt, md, screenshot
    }

    let number: Int
    let german: Bool
    let folder: String
    let topic: String
    let format: Format
    let name: String
    let date: Date

    func url(in root: URL) -> URL {
        root.appendingPathComponent(german ? "de" : "en").appendingPathComponent(folder).appendingPathComponent(name)
    }

    /// Folder, topic template, descriptive name stem. `{city}`, `{person}`, `{company}` and `{year}` are filled in.
    private static let germanTopics: [(String, String, String)] = [
        ("Finanzen", "eine Stromrechnung der Stadtwerke {city} für {year}", "Stromrechnung {year}"),
        ("Finanzen", "eine Handyrechnung eines Mobilfunkanbieters für einen Monat", "Handyrechnung"),
        ("Finanzen", "eine Mahnung wegen einer unbezahlten Rechnung von {company}", "Mahnung {company}"),
        ("Finanzen", "einen Steuerbescheid des Finanzamts {city} für {year}", "Steuerbescheid {year}"),
        ("Finanzen", "eine Spendenquittung eines gemeinnützigen Vereins aus {city}", "Spendenquittung"),
        ("Finanzen", "eine Kfz-Versicherungspolice mit Beitrag und Schadenfreiheitsklasse", "Versicherung Auto"),
        ("Finanzen", "eine Bestellbestätigung eines Onlineshops für Gartenmöbel", "Bestellung Gartenmöbel"),
        ("Finanzen", "eine Rechnung eines Handwerkers aus {city} für eine Badsanierung", "Rechnung Bad"),
        ("Finanzen", "einen Kontoauszug-Auszug mit Daueraufträgen und Lastschriften", "Kontoauszug"),
        ("Wohnung", "eine Nebenkostenabrechnung der Hausverwaltung in {city} für {year}", "Nebenkosten {year}"),
        ("Wohnung", "einen Mietvertrag für eine Zweizimmerwohnung in {city}", "Mietvertrag {city}"),
        ("Wohnung", "eine Kündigung eines Internetvertrags bei {company}", "Kündigung Internet"),
        ("Wohnung", "ein Übergabeprotokoll beim Auszug aus einer Wohnung in {city}", "Übergabeprotokoll"),
        ("Wohnung", "eine Bedienungsanleitung-Zusammenfassung für eine Waschmaschine", "Waschmaschine Anleitung"),
        ("Arbeit", "ein Protokoll eines Teammeetings bei {company} mit Aufgaben und Fristen", "Protokoll Teammeeting"),
        ("Arbeit", "ein Angebot von {company} für eine neue Firmenwebsite", "Angebot Website"),
        ("Arbeit", "einen Arbeitsvertrag als Projektmanagerin bei {company} in {city}", "Arbeitsvertrag"),
        ("Arbeit", "eine Reisekostenabrechnung für eine Dienstreise nach {city}", "Reisekosten {city}"),
        ("Arbeit", "eine Bewerbung als Grafikdesigner bei {company}", "Bewerbung {company}"),
        ("Arbeit", "eine Projektplanung mit Meilensteinen für eine App-Einführung", "Projektplan"),
        ("Arbeit", "ein Arbeitszeugnis für {person}", "Arbeitszeugnis {person}"),
        ("Arbeit", "eine Gehaltsabrechnung für einen Monat in {year}", "Gehaltsabrechnung"),
        ("Gesundheit", "einen Arztbrief einer Hausarztpraxis in {city} nach einer Untersuchung", "Arztbrief"),
        ("Gesundheit", "eine Rechnung einer Zahnarztpraxis für eine Füllung", "Zahnarzt Rechnung"),
        ("Gesundheit", "einen Impfnachweis mit Impfdaten", "Impfungen"),
        ("Gesundheit", "einen Trainingsplan aus dem Fitnessstudio für drei Monate", "Trainingsplan"),
        ("Reisen", "eine Hotelbuchungsbestätigung für ein Wochenende in {city}", "Hotel {city}"),
        ("Reisen", "einen Reiseplan für zwei Wochen Urlaub in Portugal", "Reiseplan Portugal"),
        ("Reisen", "eine Packliste für einen Campingurlaub in Schweden", "Packliste Camping"),
        ("Reisen", "eine Zugticket-Bestätigung der Bahn von {city} nach Hamburg", "Bahnticket"),
        ("Reisen", "ein Reisetagebuch über eine Wanderung in den Alpen", "Wanderung Alpen"),
        ("Küche", "ein Rezept für Omas Apfelkuchen", "Apfelkuchen"),
        ("Küche", "ein Rezept für eine vegetarische Lasagne", "Lasagne vegetarisch"),
        ("Küche", "einen Wochenplan für das Abendessen einer Familie", "Essensplan"),
        ("Küche", "eine Einkaufsliste für eine Geburtstagsfeier", "Einkaufsliste Party"),
        ("Schule", "einen Elternbrief der Grundschule in {city} zum Schulausflug", "Elternbrief Ausflug"),
        ("Schule", "ein Zeugnis der 8. Klasse eines Gymnasiums", "Zeugnis Klasse 8"),
        ("Schule", "eine Mitschrift aus einer Vorlesung über Photosynthese", "Mitschrift Biologie"),
        ("Auto", "einen Kaufvertrag für einen gebrauchten VW Golf", "Kaufvertrag Golf"),
        ("Auto", "eine Werkstattrechnung für eine Inspektion und neue Bremsbeläge", "Werkstatt Inspektion"),
        ("Auto", "einen Bußgeldbescheid wegen zu schnellen Fahrens in {city}", "Bußgeldbescheid"),
        ("Verein", "eine Einladung zur Jahreshauptversammlung des Sportvereins {city}", "Einladung Versammlung"),
        ("Verein", "ein Protokoll einer Elternbeiratssitzung", "Protokoll Elternbeirat"),
        ("Privat", "eine Hochzeitseinladung von {person}", "Hochzeit {person}"),
        ("Privat", "eine Notiz mit Geschenkideen für Weihnachten", "Geschenkideen"),
        ("Privat", "eine Garantiekarte für einen Kaffeevollautomaten", "Garantie Kaffeemaschine"),
        ("Privat", "einen Brief an die Krankenkasse wegen einer Kostenübernahme", "Brief Krankenkasse"),
        ("Privat", "eine Anleitung zum Einrichten des WLAN-Routers mit Zugangsdaten", "WLAN Router"),
    ]

    private static let englishTopics: [(String, String, String)] = [
        ("Finance", "an electricity bill from a utility company in {city}", "Electricity bill {year}"),
        ("Finance", "a car insurance renewal notice", "Car insurance"),
        ("Finance", "a receipt from an electronics store for a laptop", "Laptop receipt"),
        ("Home", "a lease agreement for a flat in {city}", "Lease {city}"),
        ("Home", "a quote from a plumber for fixing a leaking pipe", "Plumber quote"),
        ("Work", "meeting notes from a product planning session at {company}", "Planning notes"),
        ("Work", "an offer letter for a software engineer role at {company}", "Offer letter"),
        ("Work", "an expense report for a conference trip to {city}", "Expenses {city}"),
        ("Health", "a dentist appointment reminder and invoice", "Dentist"),
        ("Travel", "a hotel booking confirmation in {city}", "Hotel booking"),
        ("Travel", "an itinerary for a week in Iceland", "Iceland itinerary"),
        ("Cooking", "a recipe for banana bread", "Banana bread"),
        ("School", "lecture notes on supply and demand", "Econ notes"),
        ("Personal", "a letter to a landlord about a broken heater", "Letter landlord"),
    ]

    private static let cities = ["Leipzig", "Köln", "Freiburg", "Hannover", "Nürnberg", "Bremen", "Dresden", "Mainz",
                                 "Kassel", "Münster", "Regensburg", "Kiel"]
    private static let people = ["Anna Becker", "Jonas Wolf", "Lea Schröder", "Tim Hoffmann", "Sophie Wagner",
                                 "Paul Neumann", "Mia Schulz", "Felix Braun"]
    private static let companies = ["Nordlicht GmbH", "Bergmann & Co", "Kranich Media", "Blauwal Software",
                                    "Lindner Bau", "Fuchs Telekom", "Sonnenhof AG", "Pixelwerk"]

    static func make(number: Int, random: inout SeededRandom) -> CorpusSpec {
        let german = random.next(100) < 78
        let (folder, template, stem) = german ? random.pick(germanTopics) : random.pick(englishTopics)
        let year = 2021 + random.next(6)
        // One city, person and company per document, so its topic and its name agree.
        let (city, person, company) = (random.pick(cities), random.pick(people), random.pick(companies))
        let fill = { (text: String) in
            text.replacingOccurrences(of: "{city}", with: city).replacingOccurrences(of: "{person}", with: person)
                .replacingOccurrences(of: "{company}", with: company).replacingOccurrences(of: "{year}", with: String(year))
        }
        let topic = fill(template)
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(
            year: year, month: 1 + random.next(12), day: 1 + random.next(28), hour: 8 + random.next(12),
            minute: random.next(60), second: random.next(60)))!
        let format: Format = switch random.next(100) {
        case ..<34: .pdf
        case ..<42: .scan
        case ..<56: .docx
        case ..<61: .rtf
        case ..<74: .txt
        case ..<86: .md
        default: .screenshot
        }
        return CorpusSpec(number: number, german: german, folder: folder, topic: topic, format: format,
                          name: name(stem: fill(stem), format: format, german: german, date: date, number: number,
                                     random: &random), date: date)
    }

    /// The file name: descriptive most of the time, else what a scanner, a screenshot or an untitled save gives.
    /// Every name ends with the spec's number when it could collide, so two specs never share a file.
    private static func name(stem: String, format: Format, german: Bool, date: Date, number: Int,
                             random: inout SeededRandom) -> String {
        let day = ISO8601DateFormatter.day.string(from: date)
        let ext = format == .scan ? "pdf" : format == .screenshot ? "png" : format.rawValue
        switch format {
        case .screenshot:
            let time = String(format: "%02d.%02d.%02d", 8 + number % 12, number % 60, (number * 7) % 60)
            return german ? "Bildschirmfoto \(day) um \(time).png" : "Screenshot \(day) at \(time).png"
        case .scan:
            return "Scan \(day) \(number).pdf"
        default:
            switch random.next(100) {
            case ..<65: return "\(stem) \(number).\(ext)"
            case ..<80: return "\(day) \(stem.lowercased()).\(ext)"
            default: return german ? "Dokument \(number).\(ext)" : "Untitled \(number).\(ext)"
            }
        }
    }
}

/// A small seeded generator (SplitMix64), so the corpus specs are the same on every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<bound.
    mutating func next(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

    mutating func pick<T>(_ items: [T]) -> T { items[next(items.count)] }
}

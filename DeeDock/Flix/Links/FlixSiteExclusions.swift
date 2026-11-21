import Foundation

/// Sites link tracking never records: the person's own list, and while "Leave out banking and
/// health sites" is on, a built-in list of banks, payment services, insurers, and health portals.
///
/// Matching is by host suffix on label boundaries: `bank.example.com` also excludes
/// `login.bank.example.com`, never `notbank.example.com`. The built-in category also matches host
/// labels that contain a banking or health word (`onlinebanking-…`, `mychart.…`, `…klinik…`),
/// which errs toward leaving a page out. The exclusions apply to automatic tracking and to the pages
/// downloads came from (`FlixSourcePolicy`, which keeps not even the host); a page you save
/// yourself ("Save this page", a dropped URL) is kept, because that is a deliberate choice.
nonisolated struct FlixSiteExclusions: Equatable, Sendable {
    /// Hosts typed in Settings, lowercased, without `www.`.
    var userSites: [String]
    var excludesSensitiveCategories: Bool

    init(userSites: [String], excludesSensitiveCategories: Bool) {
        self.userSites = userSites.map(Self.normalized)
        self.excludesSensitiveCategories = excludesSensitiveCategories
    }

    init(settings: FlixSettings) {
        self.init(userSites: settings.excludedSites, excludesSensitiveCategories: settings.excludesSensitiveSites)
    }

    /// Whether a page on `host` must not be tracked.
    func excludes(host: String) -> Bool {
        let host = Self.normalized(host)
        guard !host.isEmpty else { return true }
        if userSites.contains(where: { Self.host(host, isWithin: $0) }) { return true }
        guard excludesSensitiveCategories else { return false }
        if Self.sensitiveDomains.contains(where: { Self.host(host, isWithin: $0) }) { return true }
        let labels = host.split(separator: ".").dropLast().map(String.init)
        return labels.contains { label in Self.sensitiveWords.contains { label.contains($0) } }
    }

    func excludes(_ url: URL) -> Bool {
        excludes(host: url.host(percentEncoded: false) ?? "")
    }

    /// `host` is `domain` or a subdomain of it.
    static func host(_ host: String, isWithin domain: String) -> Bool {
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    static func normalized(_ host: String) -> String {
        let lowered = host.trimmingCharacters(in: .whitespaces).lowercased()
        let trimmed = lowered.hasSuffix(".") ? String(lowered.dropLast()) : lowered
        return trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
    }

    /// Words in a host label that mark a bank, an insurer, or a health service, in English and
    /// German. Substrings, so `onlinebanking` and `sparkasse-koeln` both match.
    static let sensitiveWords = [
        "bank", "banking", "sparkasse", "volksbank", "raiffeisen", "creditunion", "kreditkarte",
        "health", "clinic", "hospital", "patient", "mychart", "pharmacy", "medical", "doctor",
        "klinik", "krankenhaus", "apotheke", "arzt", "praxis", "krankenkasse", "gesundheit",
    ]

    /// Banks, payment and investment services, insurers, and health portals whose names carry none of
    /// ``sensitiveWords``.
    static let sensitiveDomains = [
        // Payments, banks, brokers.
        "paypal.com", "chase.com", "wellsfargo.com", "citi.com", "capitalone.com", "americanexpress.com",
        "discover.com", "usbank.com", "pnc.com", "schwab.com", "fidelity.com", "vanguard.com", "robinhood.com",
        "hsbc.com", "hsbc.co.uk", "barclays.co.uk", "natwest.com", "lloydsbank.com", "santander.com",
        "ing.com", "ing.de", "dkb.de", "comdirect.de", "commerzbank.de", "deutsche-bank.de", "db.com",
        "postbank.de", "consorsbank.de", "n26.com", "revolut.com", "wise.com", "klarna.com", "venmo.com",
        "cash.app", "coinbase.com", "kraken.com", "trade-republic.com", "traderepublic.com", "scalable.capital",
        "ubs.com", "credit-suisse.com", "bnpparibas.com", "bnpparibas.fr", "unicredit.it", "intesasanpaolo.com", "rabobank.nl", "abnamro.nl",
        // Insurers and tax.
        "tk.de", "aok.de", "barmer.de", "dak.de", "allianz.de", "elster.de", "irs.gov", "hmrc.gov.uk",
        // Health portals.
        "kaiserpermanente.org", "doctolib.de", "doctolib.fr", "zocdoc.com", "teladoc.com", "cvs.com",
        "walgreens.com", "goodrx.com", "23andme.com", "healthcare.gov", "nhs.uk", "onemedical.com",
        "betterhelp.com", "talkspace.com", "jameda.de",
    ]
}

import Foundation
import Testing
@testable import DeeDock

/// Web link rules: token stripping, excluded sites, web documents, and private-window markers.
struct FlixLinkRulesTests {
    // MARK: Token stripping

    @Test(arguments: [
        ("https://app.example.com/reset?token=abc123&lang=en", "https://app.example.com/reset?lang=en"),
        ("https://example.com/cb?code=xyz&state=s1", "https://example.com/cb"),
        ("https://Example.COM:443/a?utm_source=news&id=7#section", "https://example.com/a?id=7"),
        ("https://user:pw@example.com/path?sid=1&SessionID=2", "https://example.com/path"),
        ("https://bucket.s3.amazonaws.com/f.pdf?X-Amz-Algorithm=AWS4&X-Amz-Signature=deadbeef&X-Amz-Expires=300",
         "https://bucket.s3.amazonaws.com/f.pdf"),
        ("https://acct.blob.core.windows.net/c/f.pdf?sv=2021&se=2024&sp=r&sig=abc", "https://acct.blob.core.windows.net/c/f.pdf"),
        ("https://d1.cloudfront.net/f.pdf?Expires=1&Signature=x&Key-Pair-Id=k", "https://d1.cloudfront.net/f.pdf"),
        ("https://example.com", "https://example.com/"),
        ("https://example.com/#access_token=secret", "https://example.com/"),
    ])
    func sanitizerStripsSecrets(input: String, expected: String) {
        #expect(FlixURLSanitizer.sanitize(input)?.absoluteString == expected)
    }

    @Test func sanitizerKeepsAzureLikeKeysWithoutASignature() {
        // `sv` and `sp` are ordinary parameters when no signature is present.
        #expect(FlixURLSanitizer.sanitize("https://example.com/search?sp=1&q=boots")?.absoluteString
            == "https://example.com/search?sp=1&q=boots")
    }

    @Test(arguments: ["file:///Users/x/a.pdf", "mailto:a@example.com", "javascript:alert(1)", "ftp://example.com/f"])
    func sanitizerRefusesNonWebAddresses(input: String) {
        #expect(FlixURLSanitizer.sanitize(input) == nil)
    }

    // MARK: Excluded sites

    @Test func userSitesMatchOnLabelBoundaries() {
        let exclusions = FlixSiteExclusions(userSites: ["Bank.Example.com", "www.private.dev"], excludesSensitiveCategories: false)
        #expect(exclusions.excludes(host: "bank.example.com"))
        #expect(exclusions.excludes(host: "login.bank.example.com"))
        #expect(exclusions.excludes(host: "www.private.dev"))
        #expect(!exclusions.excludes(host: "notbank.example.com"))
        #expect(!exclusions.excludes(host: "example.com"))
    }

    @Test(arguments: ["www.paypal.com", "online.sparkasse-koeln.de", "meine.dkb.de", "mychart.hospital.org",
                      "patientportal.example.com", "www.onlinebanking-volksbank.de", "app.n26.com", "www.doctolib.de"])
    func sensitiveCategoriesAreExcluded(host: String) {
        #expect(FlixSiteExclusions(userSites: [], excludesSensitiveCategories: true).excludes(host: host))
        #expect(!FlixSiteExclusions(userSites: [], excludesSensitiveCategories: false).excludes(host: host))
    }

    @Test(arguments: ["docs.google.com", "github.com", "figma.com", "news.ycombinator.com"])
    func ordinarySitesAreKept(host: String) {
        #expect(!FlixSiteExclusions(userSites: [], excludesSensitiveCategories: true).excludes(host: host))
    }

    // MARK: Web documents

    @Test(arguments: [
        ("https://docs.google.com/document/d/1AbC/edit", FlixWebDocuments.Service.googleDocs),
        ("https://docs.google.com/spreadsheets/u/0/d/1AbC/edit", .googleDocs),
        ("https://www.figma.com/design/AbC123/Brand-Kit", .figma),
        ("https://www.notion.so/team/Roadmap-0123456789abcdef0123456789abcdef", .notion),
        ("https://linear.app/dokk/issue/DEE-163/flix-files", .linear),
        ("https://contoso.sharepoint.com/:w:/r/sites/x/Doc.docx", .microsoftOffice),
        ("https://acme.atlassian.net/wiki/spaces/ENG/pages/123/Plan", .atlassian),
        ("https://acme.atlassian.net/browse/ENG-42", .atlassian),
    ])
    func webDocumentsAreRecognized(address: String, service: FlixWebDocuments.Service) {
        #expect(FlixWebDocuments.service(for: URL(string: address)!) == service)
    }

    @Test(arguments: ["https://docs.google.com/", "https://www.figma.com/files/recents", "https://linear.app/dokk/inbox",
                      "https://www.notion.so/", "https://example.com/document/d/1/edit", "https://acme.atlassian.net/jira/your-work"])
    func homePagesAreNotWebDocuments(address: String) {
        #expect(!FlixWebDocuments.isWebDocument(URL(string: address)!))
    }

    // MARK: Private windows

    @Test func privateMarkersMakeAWindowPrivate() {
        #expect(FlixBrowserPageReader.privacy(family: .chromium, title: "Inbox", labels: ["Back", "Incognito"],
                                              scanned: 50, foundAddress: true) == .private)
        #expect(FlixBrowserPageReader.privacy(family: .firefox, title: "News — Private Browsing", labels: [],
                                              scanned: 50, foundAddress: true) == .private)
        #expect(FlixBrowserPageReader.privacy(family: .chromium, title: "Neuer Tab", labels: ["Inkognito"],
                                              scanned: 50, foundAddress: true) == .private)
    }

    @Test func chromiumIsNormalOnlyWithEvidence() {
        #expect(FlixBrowserPageReader.privacy(family: .chromium, title: "Docs", labels: ["Back", "Reload"],
                                              scanned: 50, foundAddress: true) == .normal)
        // Too little of the window was read to rule a private window out.
        #expect(FlixBrowserPageReader.privacy(family: .chromium, title: "Docs", labels: [],
                                              scanned: 3, foundAddress: true) == .unknown)
        #expect(FlixBrowserPageReader.privacy(family: .chromium, title: "Docs", labels: ["Back"],
                                              scanned: 50, foundAddress: false) == .unknown)
    }

    @Test func safariIsNeverTrackedAutomatically() {
        #expect(FlixBrowserPageReader.privacy(family: .safari, title: "Docs", labels: ["Back", "Reload"],
                                              scanned: 80, foundAddress: true) == .unknown)
        #expect(!FlixBrowserFamily.safari.tracksAutomatically)
        #expect(!FlixBrowserFamily.other.tracksAutomatically)
    }

    @Test(arguments: [("example.com/path", true), ("https://example.com", true), ("Search or type URL", false),
                      ("localhost", false), ("docs.google.com/document/d/1", true), (".hidden", false)])
    func omniboxValuesAreRecognized(value: String, isAddress: Bool) {
        #expect(FlixBrowserPageReader.looksLikeAddress(value) == isAddress)
    }

    @Test func linkRelationsKeepEachItemOnce() {
        var relations = FlixLinkRelationsDocument()
        let page = URL(string: "https://portal.example.com/upload")!
        let a = UUID(), b = UUID()
        relations.record(sent: [a], to: page)
        relations.record(sent: [a, b], to: page)
        #expect(relations.sent[page.absoluteString] == [a, b])
    }
}

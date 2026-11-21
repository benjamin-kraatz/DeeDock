import Foundation
import Testing
@testable import DeeDock

/// Web link rules: token stripping, excluded sites, web documents, and private-window markers.
struct FlixLinkRulesTests {
    // MARK: Cleaning addresses

    @Test(arguments: [
        // User info, fragment, and the whole query go.
        ("https://Example.COM:443/a?utm_source=news&id=7#section", "https://example.com/a"),
        ("https://user:pw@example.com/path?sid=1&SessionID=2", "https://example.com/path"),
        ("https://bucket.s3.amazonaws.com/f.pdf?X-Amz-Algorithm=AWS4&X-Amz-Signature=deadbeef&X-Amz-Expires=300",
         "https://bucket.s3.amazonaws.com/f.pdf"),
        ("https://acct.blob.core.windows.net/c/f.pdf?sv=2021&se=2024&sp=r&sig=abc", "https://acct.blob.core.windows.net/c/f.pdf"),
        ("https://example.com/search?sp=1&q=boots", "https://example.com/search"),
        ("https://example.com", "https://example.com/"),
        ("https://example.com/#access_token=secret", "https://example.com/"),
        // Ordinary slugs mixing words and digits are names, not secrets.
        ("https://blog.example.com/2024/how-to-fix-error-404-in-nginx-2024", "https://blog.example.com/2024/how-to-fix-error-404-in-nginx-2024"),
    ])
    func sanitizerKeepsOnlySchemeHostAndPath(input: String, expected: String) {
        #expect(FlixURLSanitizer.sanitize(input)?.absoluteString == expected)
    }

    @Test(arguments: [
        "https://app.example.com/reset/8f3kQ2", "https://app.example.com/password-reset?token=abc",
        "https://example.com/account/verify-email/abc", "https://example.com/users/confirm/1",
        "https://team.example.com/invite/xyz", "https://example.com/magic-link/abc", "https://example.com/login",
        "https://example.com/sign-in", "https://example.com/oauth2/callback", "https://example.com/auth/complete",
        "https://example.com/api/token", "https://news.example.com/unsubscribe/42", "https://example.com/activate/7",
        "https://www.dropbox.com/s/abc123def456ghi/Report.pdf", "https://example.com/share/board-1",
    ])
    func credentialRoutesAreNeverStored(input: String) {
        #expect(FlixURLSanitizer.clean(URL(string: input)!) == .skipped)
        #expect(FlixURLSanitizer.sanitize(input) == nil)
    }

    @Test(arguments: [
        "https://files.example.com/d/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08/report.pdf",
        "https://portal.example.com/downloads/3f2504e0-4f89-11d3-9a0c-0305e82c3301",
        "https://example.com/x/Ab3dE6gH9jK2mN5pQ8rS1tU4",
    ])
    func highEntropySegmentsAreNeverStored(input: String) {
        #expect(FlixURLSanitizer.clean(URL(string: input)!) == .skipped)
    }

    @Test(arguments: [
        ("https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit?usp=sharing#heading=h.1",
         "https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit"),
        ("https://www.notion.so/team/Reset-Password-Flow-0123456789abcdef0123456789abcdef",
         "https://www.notion.so/team/Reset-Password-Flow-0123456789abcdef0123456789abcdef"),
        ("https://linear.app/dokk/issue/DEE-163/invite-flow", "https://linear.app/dokk/issue/DEE-163/invite-flow"),
        ("https://onedrive.live.com/edit.aspx?resid=ABC123!456&cid=789&authkey=SECRET",
         "https://onedrive.live.com/edit.aspx?resid=ABC123!456&cid=789"),
    ])
    func webDocumentsKeepTheirDocumentPath(input: String, expected: String) {
        #expect(FlixURLSanitizer.sanitize(input)?.absoluteString == expected)
    }

    @Test func webDocumentShareRoutesAreStillLeftOut() {
        #expect(FlixURLSanitizer.sanitize("https://www.notion.so/invite/0123456789abcdef0123456789abcdef") == nil)
    }

    @Test func cleaningCountsWhatItRemovesAndSkips() {
        #expect(FlixURLSanitizer.clean(URL(string: "https://example.com/reset/abc")!).removedSecrets == 1)
        #expect(FlixURLSanitizer.removedSecretCount(URL(string: "https://u:p@example.com/a?code=1&page=2#t=1")!) == 3)
    }

    @Test(arguments: ["file:///Users/x/a.pdf", "mailto:a@example.com", "javascript:alert(1)", "ftp://example.com/f"])
    func sanitizerRefusesNonWebAddresses(input: String) {
        #expect(FlixURLSanitizer.sanitize(input) == nil)
        #expect(FlixURLSanitizer.clean(URL(string: input)!) == .notWeb)
    }

    // MARK: Download pages

    private func settings(tracksLinks: Bool, excluded: [String] = []) -> FlixSettings {
        var settings = FlixSettings()
        settings.tracksLinks = tracksLinks
        settings.excludedSites = excluded
        return settings
    }

    @Test func downloadPagesFollowTheWebLinkSettings() {
        let page = URL(string: "https://billing.example.com/invoices")!
        let on = FlixSourcePolicy.allowed(page: page, host: nil, settings: settings(tracksLinks: true))
        #expect(on.page == page && on.host == "billing.example.com")
        let off = FlixSourcePolicy.allowed(page: page, host: nil, settings: settings(tracksLinks: false))
        #expect(off.page == nil && off.host == "billing.example.com")
        let excluded = FlixSourcePolicy.allowed(page: page, host: nil,
                                                settings: settings(tracksLinks: true, excluded: ["example.com"]))
        #expect(excluded.page == nil && excluded.host == nil)
        // Banking is left out by default, host and all, whether web links are on or off.
        let bank = FlixSourcePolicy.allowed(page: URL(string: "https://www.paypal.com/activity")!, host: nil,
                                            settings: settings(tracksLinks: false))
        #expect(bank.page == nil && bank.host == nil)
    }

    @Test func downloadsAreVouchedForOnlyByTheirOwnPage() {
        #expect(FlixLinkTracker.samePage(URL(string: "https://www.example.com/invoices")!,
                                         URL(string: "https://example.com/invoices/")!))
        // Another page on the same site, in another window, cannot vouch for the download.
        #expect(!FlixLinkTracker.samePage(URL(string: "https://example.com/a")!, URL(string: "https://example.com/b")!))
        #expect(!FlixLinkTracker.samePage(URL(string: "https://cdn.example.com/f")!, URL(string: "https://example.com/f")!))
        #expect(!FlixLinkTracker.samePage(URL(string: "https://example.org/a")!, URL(string: "https://example.com/a")!))
        #expect(!FlixLinkTracker.samePage(URL(string: "https://onedrive.live.com/?resid=1")!,
                                          URL(string: "https://onedrive.live.com/?resid=2")!))
    }

    /// Cleaning drops queries, so the stored addresses of two different pages can be equal; the
    /// download check compares the full addresses as they were read instead.
    @Test func aDownloadIsVouchedForOnlyByItsFullPageAddress() throws {
        let source = try #require(FlixPaths.sourcePageAndIdentity(fromWhereFroms: [
            "https://cdn.example.com/f.pdf?sig=abc", "https://portal.example.com/invoices?invoice=1",
        ]))
        #expect(source.page.absoluteString == "https://portal.example.com/invoices")
        #expect(source.identity.absoluteString == "https://portal.example.com/invoices?invoice=1")
        let event = FlixActivityEvent(path: "/w/Invoice.pdf", name: "Invoice.pdf", kind: .document, activity: .downloaded,
                                      date: .now, sourcePage: source.page, sourcePageIdentity: source.identity)
        func front(_ address: String) -> FlixBrowserPage {
            let raw = URL(string: address)!
            return FlixBrowserPage(url: FlixURLSanitizer.sanitize(raw)!, title: nil, privacy: .normal,
                                   browserBundleIdentifier: nil, pageIdentity: raw)
        }
        #expect(FlixLinkTracker.vouches(for: event, front: front("https://portal.example.com/invoices?invoice=1")))
        // The same cleaned page, but another invoice: not the page the file came from.
        #expect(!FlixLinkTracker.vouches(for: event, front: front("https://portal.example.com/invoices?invoice=2")))
        // Without the full address on either side there is nothing to verify against.
        var unread = front("https://portal.example.com/invoices?invoice=1")
        unread.pageIdentity = nil
        #expect(!FlixLinkTracker.vouches(for: event, front: unread))
        // A page the settings strip loses its full address with it.
        var settings = FlixSettings()
        settings.tracksLinks = false
        #expect(FlixSourcePolicy.apply(to: event, settings: settings).sourcePageIdentity == nil)
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

    private func evidence(title: String? = "Docs", labels: [String] = ["Back", "Reload"], complete: Bool = true)
        -> FlixBrowserWindowEvidence {
        FlixBrowserWindowEvidence(title: title, labels: labels, foundAddress: true, addressToolbarComplete: complete)
    }

    @Test func privateMarkersMakeAWindowPrivate() {
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence(title: "Inbox", labels: ["Back", "Incognito"])) == .private)
        #expect(FlixBrowserPageReader.privacy(family: .firefox, evidence: evidence(title: "News — Private Browsing", labels: [])) == .private)
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence(title: "Neuer Tab", labels: ["Inkognito"])) == .private)
        // A marker wins even when the toolbar was not read to its end.
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence(labels: ["InPrivate"], complete: false)) == .private)
    }

    @Test func normalNeedsTheIndicatorRegionReadCompletely() {
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence()) == .normal)
        // The toolbar holding the address was cut short or not found: unknown.
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence(complete: false)) == .unknown)
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: FlixBrowserWindowEvidence(title: "Docs")) == .unknown)
        // Firefox also needs the title, where it says "Private Browsing".
        #expect(FlixBrowserPageReader.privacy(family: .firefox, evidence: evidence()) == .normal)
        #expect(FlixBrowserPageReader.privacy(family: .firefox, evidence: evidence(title: nil)) == .unknown)
        #expect(FlixBrowserPageReader.privacy(family: .firefox, evidence: evidence(title: " ")) == .unknown)
    }

    @Test func safariIsNeverTrackedAutomatically() {
        #expect(FlixBrowserPageReader.privacy(family: .safari, evidence: evidence()) == .unknown)
        #expect(FlixBrowserPageReader.privacy(family: .other, evidence: evidence()) == .unknown)
        #expect(!FlixBrowserFamily.safari.tracksAutomatically)
        #expect(!FlixBrowserFamily.other.tracksAutomatically)
    }

    /// A tiny accessibility tree for the walk: a role, labels, a value, and children (nil when
    /// reading them fails).
    private final class Node {
        /// Nil when reading the role fails.
        let role: String?
        /// Nil when reading a label fails.
        var labels: [String]?
        var value: String?
        var children: [Node]?
        init(_ role: String?, labels: [String]? = [], value: String? = nil, children: [Node]? = []) {
            self.role = role
            self.labels = labels
            self.value = value
            self.children = children
        }
    }

    private func walk(_ root: Node, limit: Int = 700) -> FlixBrowserPageReader.Walk {
        FlixBrowserPageReader.walk(from: root, limit: limit, expired: { false }, role: \.role, labels: \.labels,
                                   value: \.value, webURL: { _ in nil }, children: \.children)
    }

    private func chromeWindow(toolbarChildren: [Node]?, tabs: Int = 0) -> Node {
        let tabStrip = Node("AXGroup", children: (0..<tabs).map { Node("AXRadioButton", labels: ["Tab \($0)"]) })
        let toolbar = Node("AXToolbar", children: toolbarChildren)
        return Node("AXWindow", children: [Node("AXGroup", children: [tabStrip, toolbar]), Node("AXWebArea", children: nil)])
    }

    @Test func theWalkReadsTheWholeToolbarHoldingTheAddress() {
        let omnibox = Node("AXTextField", value: "example.com/page")
        let result = walk(chromeWindow(toolbarChildren: [Node("AXButton", labels: ["Back"]), omnibox,
                                                         Node("AXGroup", children: [Node("AXButton", labels: ["Profile"])])]))
        #expect(result.address == "example.com/page")
        #expect(result.evidence.addressToolbarComplete)
        #expect(result.evidence.labels.contains("Profile"))
    }

    @Test func aToolbarThatCannotBeReadToItsEndIsNoEvidence() {
        let omnibox = Node("AXTextField", value: "example.com/page")
        // The profile button's group could not be read: the badge may sit there.
        let failed = walk(chromeWindow(toolbarChildren: [omnibox, Node("AXGroup", children: nil)]))
        #expect(failed.address != nil && !failed.evidence.addressToolbarComplete)
        // The budget ran out inside the toolbar.
        let cut = walk(chromeWindow(toolbarChildren: [omnibox] + (0..<20).map { _ in Node("AXButton") }), limit: 8)
        #expect(!cut.evidence.addressToolbarComplete)
    }

    @Test func failedReadsInTheToolbarAreNoEvidence() {
        let omnibox = Node("AXTextField", value: "example.com/page")
        func toolbarComplete(_ extra: Node) -> Bool {
            walk(chromeWindow(toolbarChildren: [omnibox, extra])).evidence.addressToolbarComplete
        }
        #expect(toolbarComplete(Node("AXButton", labels: ["Profile"])))
        // The role of the element where the badge may sit could not be read.
        #expect(!toolbarComplete(Node(nil, labels: ["Incognito"])))
        // Its title or description could not be read.
        #expect(!toolbarComplete(Node("AXButton", labels: nil)))
        // A web area in the toolbar is skipped, so that part stays unseen.
        #expect(!toolbarComplete(Node("AXWebArea")))
        // The toolbar's own child list or labels failed.
        let unreadToolbar = Node("AXWindow", children: [Node("AXToolbar", labels: nil, children: [omnibox])])
        #expect(!walk(unreadToolbar).evidence.addressToolbarComplete)
    }

    @Test func aWalkThatExpiresInTheToolbarIsNoEvidence() {
        let omnibox = Node("AXTextField", value: "example.com/page")
        var reads = 0
        let window = chromeWindow(toolbarChildren: [omnibox, Node("AXButton"), Node("AXButton", labels: ["Profile"])])
        let result = FlixBrowserPageReader.walk(from: window, limit: 700, expired: {
            reads += 1
            return reads > 6
        }, role: \.role, labels: \.labels, value: \.value, webURL: { _ in nil }, children: \.children)
        #expect(result.address != nil && !result.evidence.addressToolbarComplete)
    }

    @Test func manyTabsDoNotCrowdOutTheToolbarsLabels() {
        // 400 tabs put the window past the label cap before the toolbar is reached; the toolbar's
        // labels are still read, so the badge is seen.
        let omnibox = Node("AXTextField", value: "example.com/page")
        let tabs = (0..<400).map { Node("AXRadioButton", labels: ["Tab \($0)"]) }
        let window = Node("AXWindow", children: [Node("AXGroup", children: tabs),
                                                 Node("AXGroup", children: [Node("AXToolbar", children: [
                                                     omnibox, Node("AXButton", labels: ["Incognito"])])])])
        let result = walk(window)
        #expect(result.evidence.addressToolbarComplete)
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: result.evidence) == .private)
    }

    @Test func aTitleThatCouldNotBeReadIsNoEvidence() {
        var evidence = FlixBrowserWindowEvidence(title: nil, labels: [], foundAddress: true, addressToolbarComplete: true)
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence) == .normal)
        evidence.titleReadFailed = true
        #expect(FlixBrowserPageReader.privacy(family: .chromium, evidence: evidence) == .unknown)
        #expect(FlixBrowserPageReader.privacy(family: .firefox, evidence: evidence) == .unknown)
    }

    @Test func anAddressOutsideAToolbarIsNoEvidence() {
        let window = Node("AXWindow", children: [Node("AXGroup", children: [Node("AXTextField", value: "example.com")])])
        let result = walk(window)
        #expect(result.evidence.foundAddress && !result.evidence.addressToolbarComplete)
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

import ApplicationServices
import Foundation

/// The page in a browser's focused window, as its accessibility tree shows it.
nonisolated struct FlixBrowserPage: Equatable, Sendable {
    /// Whether the window is private, as far as Flix can tell.
    enum Privacy: Equatable, Sendable {
        case normal
        case `private`
        /// No reliable signal. Automatic tracking treats it as private.
        case unknown
    }

    /// The page address, already cleaned by ``FlixURLSanitizer``.
    var url: URL
    var title: String?
    var privacy: Privacy
    var browserBundleIdentifier: String?
    /// How many credentials cleaning removed from the address the browser showed, for the
    /// `flix_link_tokens_stripped` counter.
    var removedSecrets = 0

    var host: String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// What one walk of a browser window saw, for the private-window decision.
nonisolated struct FlixBrowserWindowEvidence: Equatable, Sendable {
    /// The window's own title.
    var title: String?
    /// Titles, descriptions, and help texts of the elements visited outside the page itself.
    var labels: [String] = []
    /// A web area's `AXURL`, or an address field's value, was found.
    var foundAddress = false
    /// The address field sat in a toolbar (`AXToolbar`), and that whole toolbar was visited: every
    /// descendant read, and every privacy-relevant read inside it (role, title, description, help,
    /// child list) answered without an error, within the budget and the label cap. That toolbar is
    /// where Chromium browsers show their private-window badge.
    var addressToolbarComplete = false
    /// Reading the window's own title failed (rather than the window having none). The title is
    /// where Firefox says "Private Browsing" and may carry another browser's marker, so a failed
    /// read is no evidence.
    var titleReadFailed = false
}

/// Reads a browser window's address, title, and private state through Accessibility.
///
/// No extension and no Apple Events (which would ask for Automation permission). One bounded
/// breadth-first walk of the window, at most ``elementLimit`` elements or ``budget`` seconds, off
/// the main actor, with a messaging timeout on every call. A toolbar is walked to its end as soon
/// as it is found, before the rest of the window, so the region that carries the private badge is
/// covered first.
/// - **Address**: a web area's `AXURL` (Safari always; Chromium and Firefox when their web tree is
///   already built), else the first text field whose value looks like an address (the omnibox or
///   URL bar, which Chromium and Firefox expose without turning on their web tree).
/// - **Private state** needs positive evidence (``privacy(family:evidence:)``). A private marker
///   ("Incognito", "InPrivate", "Private Browsing", "Privater Modus", "Privat", …) in the title or
///   any label means private. A window counts as normal only when the region where its browser
///   shows the private indicator was read completely:
///   - **Chromium** (Chrome, Edge, Brave, Vivaldi, Opera, Arc, …): the toolbar holding the omnibox,
///     where the Incognito, InPrivate, or Private badge sits next to the profile button.
///   - **Firefox** and its forks: the toolbar holding the URL bar, and the window title, which
///     Firefox ends with "Private Browsing" in a private window.
///   - **Safari and other browsers**: never; their private windows carry no marker DOKK could verify.
///   Anything less — a walk cut short by the budget, a toolbar element whose role, labels, or
///   children could not be read (each read keeps its Accessibility status, ``attribute(_:_:)``), a
///   label skipped at the cap, an address outside a toolbar, a title that could not be read, no
///   title for Firefox — is unknown, and automatic tracking treats unknown as private.
///
/// It never sets `AXEnhancedUserInterface`; callers that need a web tree switch it on for the
/// duration of one read and restore it.
nonisolated enum FlixBrowserPageReader {
    static let elementLimit = 700
    static let budget: TimeInterval = 0.3
    /// The per-call Accessibility timeout, so one busy browser cannot hold the walk.
    static let messagingTimeout: Float = 0.15

    static let privateMarkers = [
        "incognito", "inkognito", "inprivate", "private browsing", "privates surfen", "privater modus",
        "private window", "privates fenster", "navigation privée", "navegación privada", "navigazione anonima",
    ]
    /// Whole-word markers: Brave's and Firefox's badges say just "Private".
    static let privateWords: Set<String> = ["private", "privat", "privé", "privada", "privato"]
    static let titleSuffixes = [" — Mozilla Firefox", " - Mozilla Firefox", " — Firefox", " - Google Chrome",
                                " - Microsoft Edge", " - Brave", " — Zen Browser", " - Vivaldi", " - Chromium"]

    static func read(processIdentifier: pid_t, family: FlixBrowserFamily, bundleIdentifier: String?) async -> FlixBrowserPage? {
        await Task.detached(priority: .userInitiated) {
            readNow(processIdentifier: processIdentifier, family: family, bundleIdentifier: bundleIdentifier)
        }.value
    }

    /// Synchronous body of ``read(processIdentifier:family:bundleIdentifier:)``. Never call it on the
    /// main actor: a busy browser can take the whole budget.
    static func readNow(processIdentifier: pid_t, family: FlixBrowserFamily, bundleIdentifier: String?) -> FlixBrowserPage? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        guard let window = RobiAX.element(application, kAXFocusedWindowAttribute)
                ?? RobiAX.element(application, kAXMainWindowAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        let deadline = Date().addingTimeInterval(budget)
        let walk = walk(from: window, limit: elementLimit, expired: { Date() >= deadline },
                        role: { element in
                            switch attribute(element, kAXRoleAttribute) {
                            case .value(let value): value as? String ?? ""
                            case .absent: ""
                            case .failed: nil
                            }
                        },
                        labels: labels(of:),
                        value: { RobiAX.value($0, kAXValueAttribute) as? String },
                        webURL: { RobiAX.value($0, "AXURL") as? URL },
                        children: children(of:))
        var evidence = walk.evidence
        switch attribute(window, kAXTitleAttribute) {
        case .value(let value): evidence.title = value as? String
        case .absent: evidence.title = nil
        case .failed: evidence.titleReadFailed = true
        }
        guard let raw = walk.webURL ?? walk.address.flatMap(url(fromAddress:)) else { return nil }
        let cleaned = FlixURLSanitizer.clean(raw)
        guard let url = cleaned.url else {
            // A credential-bearing address is never stored; it still counts as stripped.
            if cleaned == .skipped { Task { @MainActor in Analytics.count(.linkTokensStripped) } }
            return nil
        }
        return FlixBrowserPage(url: url, title: cleanTitle(evidence.title), privacy: privacy(family: family, evidence: evidence),
                               browserBundleIdentifier: bundleIdentifier, removedSecrets: cleaned.removedSecrets)
    }

    /// One attribute read that keeps the difference between "the element has none" and "the read
    /// failed" (a timeout, a dead element, a busy app), which the private-window decision needs.
    enum AttributeRead {
        case value(CFTypeRef)
        /// The element has no value for it, or does not support it.
        case absent
        case failed
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AttributeRead {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success: return value.map(AttributeRead.value) ?? .absent
        case .noValue, .attributeUnsupported: return .absent
        default: return .failed
        }
    }

    /// An element's title, description, and help texts, or nil when any of those reads failed.
    static func labels(of element: AXUIElement) -> [String]? {
        var found: [String] = []
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            switch attribute(element, name) {
            case .value(let value):
                if let text = value as? String, !text.isEmpty { found.append(text) }
            case .absent: continue
            case .failed: return nil
            }
        }
        return found
    }

    /// The children of an element, or nil when reading them failed (a timeout, a dead element), so
    /// the walk knows it did not see that part. An element without children reads as empty. Each
    /// child gets the walk's messaging timeout before anything is asked of it.
    static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) {
        case .success:
            let children = value as? [AXUIElement] ?? []
            for child in children { AXUIElementSetMessagingTimeout(child, messagingTimeout) }
            return children
        case .noValue, .attributeUnsupported: return []
        default: return nil
        }
    }

    /// What a walk found: the evidence (without the title, which the caller reads), the web area's
    /// address, and the address field's value.
    struct Walk {
        var evidence = FlixBrowserWindowEvidence()
        var webURL: URL?
        var address: String?
    }

    /// The walk, over any tree, so its rules are testable without a browser.
    ///
    /// Breadth-first from `root`, skipping the inside of web areas (the page itself is not read). A
    /// toolbar is walked to its end the moment it is found (depth-first, same limits), so a budget
    /// cut-off lands in the rest of the window rather than in the toolbar. `role`, `labels`, and
    /// `children` return nil when their read failed. In a toolbar (the toolbar element included),
    /// any failed read, an element whose role could not be read (its children are then not read
    /// either), a web area (whose inside is not read), or the budget or element limit running out
    /// makes the toolbar incomplete, so the window's privacy stays unknown. Labels are capped at 300
    /// outside toolbars only.
    static func walk<Element>(from root: Element, limit: Int, expired: () -> Bool,
                              role: (Element) -> String?, labels: (Element) -> [String]?,
                              value: (Element) -> String?, webURL: (Element) -> URL?,
                              children: (Element) -> [Element]?) -> Walk {
        var result = Walk()
        var queue: [Element] = [root]
        var index = 0
        var visited = 0
        var labelCount = 0

        /// Reads one element. Returns its children to visit, whether any privacy-relevant read
        /// failed or was skipped, and whether it is a toolbar.
        func visit(_ element: Element, inToolbar: Bool) -> (children: [Element], failed: Bool, isToolbar: Bool) {
            visited += 1
            guard let elementRole = role(element) else {
                // Without its role the element cannot be placed; its children are not read either.
                return ([], true, false)
            }
            if elementRole == "AXWebArea" {
                if result.webURL == nil, let url = webURL(element), url.scheme?.hasPrefix("http") == true {
                    result.webURL = url
                    result.evidence.foundAddress = true
                }
                // The page itself is not read: inside a toolbar that is a part left unseen.
                return ([], true, false)
            }
            let isToolbar = elementRole == kAXToolbarRole
            if elementRole == kAXTextFieldRole || elementRole == kAXComboBoxRole, result.address == nil,
               let text = value(element), looksLikeAddress(text) {
                result.address = text
                result.evidence.foundAddress = true
            }
            var failed = false
            // Labels outside toolbars are capped; a toolbar's are always read, since a skipped one
            // could be the private badge.
            if labelCount < 300 || inToolbar || isToolbar {
                if let found = labels(element) {
                    result.evidence.labels += found
                    labelCount += found.count
                } else {
                    failed = true
                }
            }
            guard let kids = children(element) else { return ([], true, isToolbar) }
            return (kids, failed, isToolbar)
        }

        /// Walks a toolbar's whole subtree. Returns whether it finished and whether the address
        /// field was found inside it.
        func walkToolbar(_ toolbarChildren: [Element]) -> (complete: Bool, holdsAddress: Bool) {
            let hadAddress = result.address != nil
            var stack = Array(toolbarChildren.reversed())
            var complete = true
            while let element = stack.popLast() {
                guard visited < limit, !expired() else { return (false, !hadAddress && result.address != nil) }
                let read = visit(element, inToolbar: true)
                if read.failed { complete = false }
                stack.append(contentsOf: read.children.reversed())
            }
            return (complete, !hadAddress && result.address != nil)
        }

        while index < queue.count, visited < limit, !expired() {
            let element = queue[index]
            index += 1
            let read = visit(element, inToolbar: false)
            if read.isToolbar {
                // The toolbar's own reads count too: a failed child list or label read leaves it unseen.
                var toolbar = walkToolbar(read.children)
                if read.failed { toolbar.complete = false }
                if toolbar.holdsAddress { result.evidence.addressToolbarComplete = toolbar.complete }
                continue
            }
            queue.append(contentsOf: read.children)
        }
        return result
    }

    /// The private-window decision for a family, from what the walk saw. See the type's
    /// documentation for what counts as evidence per browser.
    static func privacy(family: FlixBrowserFamily, evidence: FlixBrowserWindowEvidence) -> FlixBrowserPage.Privacy {
        let texts = ([evidence.title].compactMap { $0 } + evidence.labels).map { $0.lowercased() }
        if texts.contains(where: isPrivateMarker) { return .private }
        if evidence.titleReadFailed { return .unknown }
        switch family {
        case .chromium:
            return evidence.addressToolbarComplete ? .normal : .unknown
        case .firefox:
            let hasTitle = evidence.title.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
            return evidence.addressToolbarComplete && hasTitle ? .normal : .unknown
        case .safari, .other:
            return .unknown
        }
    }

    static func isPrivateMarker(_ text: String) -> Bool {
        if privateMarkers.contains(where: text.contains) { return true }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: privateWords.contains)
    }

    static func looksLikeAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4, trimmed.count < 4_096, !trimmed.contains(" ") else { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
        let host = trimmed.split(separator: "/").first.map(String.init) ?? ""
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
            && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }
    }

    /// An omnibox value without a scheme ("example.com/path") becomes an https address.
    static func url(fromAddress value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
    }

    static func cleanTitle(_ title: String?) -> String? {
        guard var title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        for suffix in titleSuffixes where title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
        return title.isEmpty ? nil : String(title.prefix(300))
    }
}

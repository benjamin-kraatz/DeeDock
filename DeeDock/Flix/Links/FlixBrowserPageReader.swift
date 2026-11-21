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

    var host: String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Reads a browser window's address, title, and private state through Accessibility.
///
/// No extension and no Apple Events (which would ask for Automation permission). One bounded
/// breadth-first walk of the window, at most ``elementLimit`` elements or ``budget`` seconds, off
/// the main actor:
/// - **Address**: a web area's `AXURL` (Safari always; Chromium and Firefox when their web tree is
///   already built), else the first text field whose value looks like an address (the omnibox or
///   URL bar, which Chromium and Firefox expose without turning on their web tree).
/// - **Private state**: a private marker ("Incognito", "InPrivate", "Private Browsing", "Privater
///   Modus", "Privat", …) in the title or any toolbar label means private. Chromium and Firefox
///   count as normal only when the walk read the toolbar (at least ``evidenceLimit`` elements and an
///   address field or web area) without a marker; anything less is unknown. Safari and other
///   browsers are always unknown: their private windows carry no marker DOKK could verify.
///
/// It never sets `AXEnhancedUserInterface`; callers that need a web tree use
/// `RobiWebAccessibility.enable` for the duration of one read and restore it.
nonisolated enum FlixBrowserPageReader {
    static let elementLimit = 700
    static let budget: TimeInterval = 0.3
    static let evidenceLimit = 12

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
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let window = RobiAX.element(application, kAXFocusedWindowAttribute)
                ?? RobiAX.element(application, kAXMainWindowAttribute) else { return nil }
        let title = RobiAX.value(window, kAXTitleAttribute) as? String
        let deadline = Date().addingTimeInterval(budget)
        var queue: [AXUIElement] = [window]
        var index = 0
        var webURL: URL?
        var address: String?
        var labels: [String] = []
        while index < queue.count, index < elementLimit, Date() < deadline {
            let element = queue[index]
            index += 1
            let role = RobiAX.value(element, kAXRoleAttribute) as? String ?? ""
            if role == "AXWebArea" {
                if webURL == nil, let url = RobiAX.value(element, "AXURL") as? URL, url.scheme?.hasPrefix("http") == true {
                    webURL = url
                }
                // The page itself is not read.
                continue
            }
            if role == kAXTextFieldRole || role == kAXComboBoxRole, address == nil,
               let value = RobiAX.value(element, kAXValueAttribute) as? String, looksLikeAddress(value) {
                address = value
            }
            if labels.count < 300 {
                for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    if let text = RobiAX.value(element, key) as? String, !text.isEmpty { labels.append(text) }
                }
            }
            queue.append(contentsOf: RobiAX.children(element))
        }
        guard let raw = webURL ?? address.flatMap(url(fromAddress:)), let url = FlixURLSanitizer.sanitize(raw) else { return nil }
        let privacy = privacy(family: family, title: title, labels: labels, scanned: index,
                              foundAddress: webURL != nil || address != nil)
        return FlixBrowserPage(url: url, title: cleanTitle(title), privacy: privacy, browserBundleIdentifier: bundleIdentifier)
    }

    static func privacy(family: FlixBrowserFamily, title: String?, labels: [String], scanned: Int,
                        foundAddress: Bool) -> FlixBrowserPage.Privacy {
        let texts = ([title].compactMap { $0 } + labels).map { $0.lowercased() }
        if texts.contains(where: isPrivateMarker) { return .private }
        guard family.tracksAutomatically else { return .unknown }
        return scanned >= evidenceLimit && foundAddress ? .normal : .unknown
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

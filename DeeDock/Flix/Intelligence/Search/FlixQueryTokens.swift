import Foundation

/// Turns an understood search into the tokens the search head shows ("↓ Downloaded", "Last 7
/// days", "about “contract”"). Each token carries the Smart Filter rule it stands for, so removing
/// one widens the search and a search can be saved as a filter unchanged.
@MainActor
enum FlixQueryTokens {
    static func tokens(for understanding: FlixQueryUnderstanding) -> [FlixQueryToken] {
        var tokens: [FlixQueryToken] = []
        if let activity = understanding.activity, let filter = filterActivity(activity) {
            tokens.append(FlixQueryToken(label: "\(Self.arrow(activity)) " + String(localized: filter.title),
                                         rule: .activity(activity)))
        }
        for kind in understanding.kinds {
            tokens.append(FlixQueryToken(label: kindLabel(kind), rule: .kind(kind)))
        }
        for ext in understanding.extensions {
            tokens.append(FlixQueryToken(label: String(localized: .flixTokenExtension(ext.uppercased())),
                                         rule: .fileExtension(ext)))
        }
        if let days = understanding.days {
            tokens.append(FlixQueryToken(label: timeLabel(understanding.timePhrase ?? .days(days)), rule: .withinDays(days)))
        }
        if let amount = understanding.minimumAmount {
            let text = amount.formatted(.currency(code: understanding.currency ?? "EUR").precision(.fractionLength(0)))
            tokens.append(FlixQueryToken(label: String(localized: .flixTokenOver(text)), rule: .amountOver(amount)))
        }
        if let folder = understanding.folder {
            tokens.append(FlixQueryToken(label: String(localized: .flixTokenInFolder(folder)), rule: .locationContains(folder)))
        }
        if let site = understanding.site {
            tokens.append(FlixQueryToken(label: String(localized: .flixTokenFromSite(site)), rule: .sourceContains(site)))
        }
        if let topic = understanding.topic, !topic.isEmpty {
            tokens.append(FlixQueryToken(label: String(localized: .flixTokenAbout(topic)), rule: .about(topic)))
        }
        return tokens
    }

    static func kindLabel(_ kind: FlixItemKind) -> String {
        switch kind {
        case .screenshot: String(localized: FlixFilter.Kind.screenshots.title)
        case .image: String(localized: FlixFilter.Kind.images.title)
        case .document: String(localized: FlixFilter.Kind.documents.title)
        case .folder: String(localized: FlixFilter.Kind.folders.title)
        case .app: String(localized: FlixFilter.Kind.apps.title)
        case .link: String(localized: .flixTokenLinks)
        case .other: String(localized: .flixTokenOther)
        }
    }

    static func timeLabel(_ phrase: FlixTimePhrase) -> String {
        switch phrase {
        case .today: String(localized: .flixTokenToday)
        case .yesterday: String(localized: .flixTokenSinceYesterday)
        case .week: String(localized: .flixTokenLastDays(7))
        case .month: String(localized: .flixTokenLastDays(30))
        case .days(let days): String(localized: .flixTokenLastDays(days))
        }
    }

    private static func filterActivity(_ activity: FlixActivity) -> FlixFilter.Activity? {
        switch activity {
        case .opened: .opened
        case .downloaded: .downloaded
        case .created: .created
        case .saved: .saved
        case .link, .kept: nil
        }
    }

    private static func arrow(_ activity: FlixActivity) -> String {
        switch activity {
        case .opened: "↗"
        case .downloaded: "↓"
        case .created: "＋"
        case .saved: "✎"
        case .link, .kept: ""
        }
    }
}

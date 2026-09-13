import Foundation

/// DDock's own windows, offered next to apps so they can be found without the menu bar.
nonisolated enum LauncherTool: String, CaseIterable, Identifiable, Sendable {
    case clipboardMuseum, localHistory, fusion, systemSettingsClone
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .clipboardMuseum: .clipboardMuseumTitle
        case .localHistory: .timelineTitle
        case .fusion: .fusionTitle
        case .systemSettingsClone: .systemSettingsCloneTitle
        }
    }

    var symbol: String {
        switch self {
        case .clipboardMuseum: "building.columns"
        case .localHistory: "clock.arrow.circlepath"
        case .fusion: "square.on.square.intersection.dashed"
        case .systemSettingsClone: "gearshape.2"
        }
    }

    /// Tools whose localized title contains every typed term.
    static func matching(_ query: String) -> [Self] {
        let terms = LauncherApplication.normalize(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return allCases.filter { tool in
            let title = LauncherApplication.normalize(String(localized: tool.title))
            return terms.allSatisfy { title.contains($0) }
        }
    }
}

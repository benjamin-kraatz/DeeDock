import Foundation

/// Ordered, optional preparation steps owned by one Dock Mode.
///
/// Opening an app or file records that macOS accepted the handoff. It does not mean a document
/// finished loading or a Shortcut completed every side effect the user cares about.
nonisolated struct WorkspaceRecipe: Codable, Equatable, Sendable {
    /// Keeps a recipe short enough to review, cancel, and repair by hand.
    static let maximumStepCount = 12
    static let maximumBookmarkBytes = 65_536
    static let empty = WorkspaceRecipe(steps: [])

    var steps: [WorkspaceRecipeStep]

    var isEmpty: Bool { steps.isEmpty }

    /// Drops unknown or incomplete steps and enforces the persisted bound.
    var sanitized: WorkspaceRecipe {
        WorkspaceRecipe(steps: Self.sanitize(steps))
    }

    /// True when this recipe can be written without corrupting an otherwise valid modes document.
    var isPersistable: Bool {
        sanitized == self
    }

    static func sanitize(_ steps: [WorkspaceRecipeStep]) -> [WorkspaceRecipeStep] {
        var seen = Set<UUID>()
        var result: [WorkspaceRecipeStep] = []
        for step in steps {
            guard result.count < maximumStepCount, seen.insert(step.id).inserted, step.isPersistable else { continue }
            result.append(step)
        }
        return result
    }
}

/// One configured preparation action. Identifiers stay stable across rename and reorder.
nonisolated enum WorkspaceRecipeStep: Equatable, Identifiable, Sendable {
    case application(id: UUID, application: ApplicationReference)
    case resource(id: UUID, bookmark: Data, name: String)
    case link(id: UUID, url: String)
    case shortcut(id: UUID, shortcutID: UUID, name: String)

    var id: UUID {
        switch self {
        case .application(let id, _), .resource(let id, _, _), .link(let id, _), .shortcut(let id, _, _):
            id
        }
    }

    /// User-facing name supplied by macOS, the picker, or the saved Shortcut title.
    var title: String {
        switch self {
        case .application(_, let application): application.name
        case .resource(_, _, let name): name
        case .link(_, let url): url
        case .shortcut(_, _, let name): name
        }
    }

    var symbolName: String {
        switch self {
        case .application: "app"
        case .resource: "folder"
        case .link: "link"
        case .shortcut: "bolt.square.fill"
        }
    }

    var isPersistable: Bool {
        switch self {
        case .application(_, let application):
            !application.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .resource(_, let bookmark, let name):
            !bookmark.isEmpty && bookmark.count <= WorkspaceRecipe.maximumBookmarkBytes
                && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .link(_, let url):
            WorkspaceRecipeLink.normalized(url) != nil
        case .shortcut(_, _, let name):
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

extension WorkspaceRecipeStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id, application, bookmark, name, url, shortcutID
    }

    private enum Kind: String, Codable {
        case application, resource, link, shortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .application:
            self = .application(id: id, application: try container.decode(ApplicationReference.self, forKey: .application))
        case .resource:
            self = .resource(id: id, bookmark: try container.decode(Data.self, forKey: .bookmark),
                             name: try container.decode(String.self, forKey: .name))
        case .link:
            self = .link(id: id, url: try container.decode(String.self, forKey: .url))
        case .shortcut:
            self = .shortcut(id: id, shortcutID: try container.decode(UUID.self, forKey: .shortcutID),
                             name: try container.decode(String.self, forKey: .name))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch self {
        case .application(_, let application):
            try container.encode(Kind.application, forKey: .kind)
            try container.encode(application, forKey: .application)
        case .resource(_, let bookmark, let name):
            try container.encode(Kind.resource, forKey: .kind)
            try container.encode(bookmark, forKey: .bookmark)
            try container.encode(name, forKey: .name)
        case .link(_, let url):
            try container.encode(Kind.link, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .shortcut(_, let shortcutID, let name):
            try container.encode(Kind.shortcut, forKey: .kind)
            try container.encode(shortcutID, forKey: .shortcutID)
            try container.encode(name, forKey: .name)
        }
    }
}

nonisolated extension WorkspaceRecipe {
    private enum CodingKeys: String, CodingKey { case steps }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = Self.sanitize(Self.decodeSteps(from: container))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sanitized.steps, forKey: .steps)
    }

    /// Unknown or unreadable steps are dropped so one bad entry cannot lock the rest of the mode.
    private static func decodeSteps(from container: KeyedDecodingContainer<CodingKeys>) -> [WorkspaceRecipeStep] {
        guard var unkeyed = try? container.nestedUnkeyedContainer(forKey: .steps) else { return [] }
        var steps: [WorkspaceRecipeStep] = []
        while !unkeyed.isAtEnd {
            let index = unkeyed.currentIndex
            if let step = try? unkeyed.decode(WorkspaceRecipeStep.self) {
                steps.append(step)
            } else {
                _ = try? unkeyed.decode(WorkspaceRecipeSkippedValue.self)
                if unkeyed.currentIndex == index { break }
            }
        }
        return steps
    }
}

/// Consumes one unreadable JSON value so a later valid step can still decode.
nonisolated private struct WorkspaceRecipeSkippedValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        if (try? container.decode(String.self)) != nil { return }
        if (try? container.decode([WorkspaceRecipeSkippedValue].self)) != nil { return }
        _ = try? container.decode([String: WorkspaceRecipeSkippedValue].self)
    }
}

/// Accepts only explicit http(s) links. Other schemes never become a recipe step.
nonisolated enum WorkspaceRecipeLink {
    static func normalized(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

/// A repairable problem discovered before a step runs. Other steps stay editable.
enum WorkspaceRecipeIssue: Equatable {
    case missingApplication
    case staleBookmark
    case invalidLink
    case missingShortcut

    var message: LocalizedStringResource {
        switch self {
        case .missingApplication: .recipeAppMissing
        case .staleBookmark: .recipeBookmarkStale
        case .invalidLink: .recipeURLInvalid
        case .missingShortcut: .recipeShortcutMissing
        }
    }
}

extension WorkspaceRecipeStep {
    /// Reports a repairable problem without running the step. Enumeration is optional for Shortcuts.
    func issue(resolvedURL: (ApplicationReference) -> URL?, knowsShortcut: (UUID) -> Bool,
               shortcutsEnumerated: Bool) -> WorkspaceRecipeIssue? {
        switch self {
        case .application(_, let application):
            return resolvedURL(application) == nil ? .missingApplication : nil
        case .resource(_, let bookmark, _):
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                     relativeTo: nil, bookmarkDataIsStale: &stale), !stale else {
                return .staleBookmark
            }
            return FileManager.default.fileExists(atPath: url.path) ? nil : .staleBookmark
        case .link(_, let url):
            return WorkspaceRecipeLink.normalized(url) == nil ? .invalidLink : nil
        case .shortcut(_, let shortcutID, _):
            return shortcutsEnumerated && !knowsShortcut(shortcutID) ? .missingShortcut : nil
        }
    }
}

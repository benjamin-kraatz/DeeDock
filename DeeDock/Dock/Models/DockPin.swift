import Foundation

/// One persisted entry in a display's pinned section.
nonisolated enum DockPin: Equatable, Identifiable, Sendable {
    case application(ApplicationReference)
    case folder(FolderReference)

    var id: String {
        switch self {
        case .application(let reference): reference.id
        case .folder(let reference): "folder:\(reference.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .application(let reference): reference.name
        case .folder(let reference): reference.name
        }
    }

    var application: ApplicationReference? {
        if case .application(let reference) = self { return reference }
        return nil
    }

    var folder: FolderReference? {
        if case .folder(let reference) = self { return reference }
        return nil
    }
}

extension DockPin: Codable {
    private enum CodingKeys: String, CodingKey { case kind, application, folder }
    private enum Kind: String, Codable { case application, folder }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .application:
            self = .application(try container.decode(ApplicationReference.self, forKey: .application))
        case .folder:
            self = .folder(try container.decode(FolderReference.self, forKey: .folder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .application(let reference):
            try container.encode(Kind.application, forKey: .kind)
            try container.encode(reference, forKey: .application)
        case .folder(let reference):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(reference, forKey: .folder)
        }
    }
}

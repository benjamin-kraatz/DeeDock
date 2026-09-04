import Foundation

/// The local model's readiness as exposed to feature state.
nonisolated enum SemanticStackAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
}

/// Metadata for one item. The model never receives its URL, bookmark, or contents.
nonisolated struct SemanticStackCandidate: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: String
    let contentType: String?
    let isDirectory: Bool
    let byteCount: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let addedAt: Date?
}

/// One independently cached organization request.
nonisolated struct SemanticStackRequest: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case folder(UUID)
        case shelf
    }

    let source: Source
    let candidates: [SemanticStackCandidate]
    let localeIdentifier: String
}

/// A stable section emitted while semantic organization progresses.
nonisolated struct SemanticStackSection: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case generated
        case other
        case organizing
        case moreItems
        case unavailable
        case items
    }

    let id: String
    let title: String
    let itemIDs: [String]
    let kind: Kind
}

/// A complete display snapshot. Partial snapshots still contain every candidate exactly once.
nonisolated struct SemanticStackSnapshot: Equatable, Sendable {
    let sections: [SemanticStackSection]
    let isFinal: Bool
}

/// Raw typed-generation values after removing Foundation Models implementation details.
nonisolated struct SemanticStackProposedGroup: Equatable, Sendable {
    let title: String?
    let itemNumbers: [Int]
}

/// Shared boundary used by folder stacks and the Shelf. Tests replace it with a deterministic fake.
nonisolated protocol SemanticStackOrganizing: Sendable {
    func availability() async -> SemanticStackAvailability
    func snapshots(for request: SemanticStackRequest) async -> AsyncThrowingStream<SemanticStackSnapshot, Error>
}

nonisolated enum SemanticStackGenerationError: Error, Sendable {
    case modelUnavailable
}

/// Preview and test default that never starts a live model session.
nonisolated struct UnavailableSemanticStackOrganizer: SemanticStackOrganizing {
    func availability() async -> SemanticStackAvailability { .modelNotReady }

    func snapshots(for request: SemanticStackRequest) async -> AsyncThrowingStream<SemanticStackSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: SemanticStackGenerationError.modelUnavailable) }
    }
}

/// Repairs partial or imperfect model output before feature state sees it.
nonisolated enum SemanticStackNormalizer {
    static func snapshot(
        candidates: [SemanticStackCandidate],
        proposedGroups: [SemanticStackProposedGroup],
        isFinal: Bool,
        otherTitle: String,
        organizingTitle: String
    ) -> SemanticStackSnapshot {
        let candidatesByNumber = Dictionary(uniqueKeysWithValues:
            candidates.enumerated().map { ($0.offset + 1, $0.element) })
        var assigned = Set<String>()
        var titleIndices: [String: Int] = [:]
        var sections: [SemanticStackSection] = []

        for (index, proposed) in proposedGroups.enumerated() {
            let title = proposed.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { continue }
            let ids = proposed.itemNumbers.compactMap { candidatesByNumber[$0]?.id }
                .filter { assigned.insert($0).inserted }
            guard !ids.isEmpty else { continue }

            let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                locale: .current)
            if let existing = titleIndices[normalizedTitle] {
                let section = sections[existing]
                sections[existing] = SemanticStackSection(
                    id: section.id,
                    title: section.title,
                    itemIDs: alphabetized(section.itemIDs + ids, candidates: candidates),
                    kind: .generated
                )
            } else {
                titleIndices[normalizedTitle] = sections.count
                sections.append(SemanticStackSection(
                    id: "generated-\(index)",
                    title: title,
                    itemIDs: alphabetized(ids, candidates: candidates),
                    kind: .generated
                ))
            }
        }

        let unassigned = alphabetized(candidates.map(\.id).filter { !assigned.contains($0) },
                                      candidates: candidates)
        if !unassigned.isEmpty {
            sections.append(SemanticStackSection(
                id: isFinal ? "other" : "organizing",
                title: isFinal ? otherTitle : organizingTitle,
                itemIDs: unassigned,
                kind: isFinal ? .other : .organizing
            ))
        }
        return SemanticStackSnapshot(sections: sections, isFinal: isFinal)
    }

    static func fallback(candidates: [SemanticStackCandidate], title: String) -> SemanticStackSnapshot {
        guard !candidates.isEmpty else { return SemanticStackSnapshot(sections: [], isFinal: true) }
        return SemanticStackSnapshot(sections: [SemanticStackSection(
            id: "items",
            title: title,
            itemIDs: alphabetized(candidates.map(\.id), candidates: candidates),
            kind: .items
        )], isFinal: true)
    }

    private static func alphabetized(_ ids: [String], candidates: [SemanticStackCandidate]) -> [String] {
        let names = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.name) })
        return ids.sorted { lhs, rhs in
            let left = names[lhs] ?? lhs
            let right = names[rhs] ?? rhs
            let comparison = left.localizedStandardCompare(right)
            return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
        }
    }
}

/// Reads only URL resource metadata. It never opens or reads file contents.
nonisolated enum SemanticStackMetadataLoader {
    static func candidate(id: String, name: String, url: URL, isDirectory: Bool,
                          addedAt: Date? = nil) -> SemanticStackCandidate {
        let keys: Set<URLResourceKey> = [
            .typeIdentifierKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        return SemanticStackCandidate(
            id: id,
            name: name,
            kind: isDirectory ? "folder" : (url.pathExtension.isEmpty ? "file" : url.pathExtension),
            contentType: values?.typeIdentifier,
            isDirectory: isDirectory,
            byteCount: values?.fileSize.map(Int64.init),
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            addedAt: addedAt
        )
    }
}

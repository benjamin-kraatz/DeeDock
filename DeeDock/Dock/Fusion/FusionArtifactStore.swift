import Foundation

/// Writes user-approved UTF-8 text artifacts to Application Support. Shelf retains a bookmark.
/// Removing a Shelf reference deliberately does not delete the user's saved artifact.
actor FusionArtifactStore {
    func write(_ draft: FusionDraft) throws -> URL {
        guard draft.isValid else { throw FusionFailure.saveFailed }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "DeeDock", isDirectory: true)
            .appendingPathComponent("Fusion", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = draft.title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined().prefix(70)
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).txt")
        let provenance = draft.sources.enumerated().map { index, source in
            ["\(index + 1). \(source.application) — \(source.title)",
             source.bundleIdentifier ?? "",
             source.capturedAt?.ISO8601Format() ?? String(localized: .fusionNotCaptured),
             String(localized: source.state.label),
             source.edited ? String(localized: .fusionEditedInput) : ""].filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let text = [draft.title, String(localized: draft.operation.label), draft.body,
                    String(localized: .fusionLimitations),
                    String(localized: .fusionGeneratedOn) + " " + draft.generatedAt.ISO8601Format(),
                    String(localized: .fusionSources), provenance].joined(separator: "\n\n")
        // Foundation forbids combining .atomic and .withoutOverwriting. This UUID-named
        // app-owned destination is new; source URLs never enter this writer.
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FusionFailure.saveFailed }
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Roll back only the file created by this save attempt if Shelf rejects its reference.
    func discard(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}

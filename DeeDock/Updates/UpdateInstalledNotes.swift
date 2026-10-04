import Foundation

/// Release notes for the versions an automatic install skipped past.
///
/// The appcast carries only the newest release, so the notes of earlier versions are not in
/// the feed. This reads the repository's release index to find the versions in between and
/// then each version's `DDock.md` asset. It runs only when the user opens the changelog.
/// Without the index it still shows the notes of the running version.
nonisolated enum UpdateInstalledNotes {
    /// Bounds the window for someone who returns after many releases.
    nonisolated static let maximumVersions = 6
    nonisolated static let maximumIndexBytes = 1024 * 1024
    /// Line that starts the English half of a bilingual notes file.
    nonisolated private static let englishMarker = "## English"

    /// Versions newer than `previous` up to and including `current`, newest first.
    /// Comparison is numeric per component, so 0.10.0 sorts after 0.9.3.
    nonisolated static func versions(in available: [String], after previous: String, through current: String) -> [String] {
        available
            .filter { isVersion($0) && compare($0, previous) == .orderedDescending
                && compare($0, current) != .orderedDescending }
            .sorted { compare($0, $1) == .orderedDescending }
            .prefix(maximumVersions)
            .map { $0 }
    }

    /// Published versions named by a GitHub releases index. Drafts and prereleases are left out.
    nonisolated static func publishedVersions(inIndex data: Data) -> [String] {
        struct Release: Decodable {
            let tag_name: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return [] }
        return releases
            .filter { $0.draft != true && $0.prerelease != true }
            .map { $0.tag_name.hasPrefix("v") ? String($0.tag_name.dropFirst()) : $0.tag_name }
            .filter(isVersion)
    }

    /// The German or English half of a bilingual file. Files without the English marker
    /// are returned whole.
    nonisolated static func localized(_ text: String, german: Bool) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let marker = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == englishMarker }) else {
            return text
        }
        let half = german ? lines[..<marker] : lines[(marker + 1)...]
        return half.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renders one heading per version followed by its notes. Returns nil when no notes
    /// could be fetched or the task was cancelled.
    @concurrent static func load(after previous: String, through current: String, german: Bool) async -> [UpdateReleaseNoteBlock]? {
        var published: [String] = []
        if let index = UpdateComicResourcePolicy.releasesIndexURL,
           let data = await UpdateComicLoader.download(index, limit: maximumIndexBytes) {
            published = publishedVersions(inIndex: data)
        }
        var wanted = versions(in: published, after: previous, through: current)
        if wanted.isEmpty { wanted = [current] }
        var blocks: [UpdateReleaseNoteBlock] = []
        for version in wanted {
            guard !Task.isCancelled else { return nil }
            guard let url = UpdateComicResourcePolicy.notesURL(version: version),
                  let data = await UpdateComicLoader.download(url, limit: UpdateReleaseNotes.maximumBytes),
                  let text = String(data: data, encoding: .utf8),
                  let notes = await UpdateReleaseNotes.render(localized(text, german: german), format: "markdown")
            else { continue }
            // Product name and version number are not translated.
            blocks.append(UpdateReleaseNoteBlock(style: .heading(2), text: AttributedString("DOKK \(version)")))
            blocks.append(contentsOf: notes)
        }
        guard !Task.isCancelled, !blocks.isEmpty else { return nil }
        return blocks.enumerated().map { index, block in
            var block = block
            block.id = index
            return block
        }
    }

    nonisolated private static func isVersion(_ name: String) -> Bool {
        name.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil
    }

    nonisolated private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}

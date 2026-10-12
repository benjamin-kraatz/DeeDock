import Foundation

/// The rules for folders Lookout may read, shared by onboarding and Settings: what's refused, what an added folder
/// does to the folders already chosen, and which folders make macOS ask first.
nonisolated enum LookoutFolderChoice {
    /// Why a folder can't be chosen.
    enum Refusal: Equatable, Sendable {
        /// `/`: every volume and the system.
        case wholeDisk
        /// The home folder itself: it holds ~/Library and everything else at once.
        case homeFolder
        /// ~/Library or a folder inside it, which Lookout never reads.
        case library
    }

    /// What choosing a folder does.
    enum Outcome: Equatable, Sendable {
        /// Add `path`; the chosen folders in `replacing` are inside it and go.
        case add(String, replacing: [String])
        /// A chosen folder already covers it.
        case alreadyIncluded(by: String)
        case refused(Refusal)
    }

    /// An absolute path, standardized, without a trailing slash.
    static func normalized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    /// Why `path` can't be chosen, or nil when it can.
    static func refusal(for path: String, home: String) -> Refusal? {
        let path = normalized(path)
        let home = normalized(home)
        if !Rules.isAllowedRoot(path) { return .wholeDisk }
        if path == home { return .homeFolder }
        let library = home + "/Library"
        if path == library || FolderSelection.isInside(path, library) { return .library }
        return nil
    }

    /// What choosing `path` does, given the folders already `chosen`. A folder inside a chosen one adds nothing; a
    /// folder around chosen ones replaces them, so nothing is listed (or read) twice.
    static func choose(_ path: String, chosen: [String], home: String) -> Outcome {
        let path = normalized(path)
        if let refusal = refusal(for: path, home: home) { return .refused(refusal) }
        let chosen = chosen.map(normalized)
        if let parent = chosen.first(where: { $0 == path || FolderSelection.isInside(path, $0) }) {
            return .alreadyIncluded(by: parent)
        }
        return .add(path, replacing: chosen.filter { FolderSelection.isInside($0, path) })
    }

    /// Whether reading `path` may make macOS show its Files and Folders prompt: Desktop, Documents and Downloads,
    /// iCloud Drive, and other volumes (removable and network ones are protected). Onboarding never reads these
    /// before the access step, and asks for them there in context. Other folders in the home folder (Pictures,
    /// a project folder) read without a prompt.
    static func needsPrompt(_ path: String, home: String) -> Bool {
        let path = normalized(path)
        let home = normalized(home)
        let protected = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].map { home + "/" + $0 }
        if protected.contains(where: { path == $0 || FolderSelection.isInside(path, $0) }) { return true }
        return path == "/Volumes" || FolderSelection.isInside(path, "/Volumes")
    }

    /// The four folders onboarding lists first: Desktop, Documents and Downloads checked, Pictures not.
    static func suggestions(home: String) -> [LookoutSetupFolder] {
        let home = normalized(home)
        let folders: [(LookoutSetupFolder.Suggestion, String, Bool)] = [
            (.desktop, "Desktop", true), (.documents, "Documents", true), (.downloads, "Downloads", true),
            (.pictures, "Pictures", false),
        ]
        return folders.map { suggestion, name, chosen in
            let path = home + "/" + name
            return LookoutSetupFolder(path: path, suggestion: suggestion, needsPrompt: needsPrompt(path, home: home),
                                      isChosen: chosen)
        }
    }
}

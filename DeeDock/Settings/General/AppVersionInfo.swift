import Foundation

/// Version values come from the built product, so Settings and update messages never duplicate
/// `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in source code.
struct AppVersionInfo: Equatable {
    let version: String
    let build: String?
    /// Short git commit of the checkout that produced this build, stamped by the
    /// "Stamp git commit" build phase (`scripts/stamp-git-commit.sh`); `nil` when the
    /// resource is missing. Ends in `-dirty` when the checkout had uncommitted changes.
    let commit: String?

    static let current = AppVersionInfo(bundle: .main)

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        commit = bundle.url(forResource: "GitCommit", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty || $0 == "unknown" ? nil : $0 }
    }

    /// "0.9.2 (33) · 88a2dd9": version, build, and the commit when known.
    var settingsValue: String {
        var value = version
        if let build, !build.isEmpty { value += " (\(build))" }
        if let commit { value += " · \(commit)" }
        return value
    }
}

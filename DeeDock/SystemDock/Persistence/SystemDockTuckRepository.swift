import Foundation

/// Stores `SystemDockTuckRecord` in DOKK's own preferences, apart from dock settings, so
/// **Restore Defaults** and unreadable dock settings never touch it.
struct SystemDockTuckRepository {
    static let key = "systemDockTuck.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// An unreadable record loads as nil rather than as an empty one, so the caller can tell
    /// "never used" apart from "lost track of what was changed".
    func load() -> SystemDockTuckRecord? {
        guard let data = defaults.data(forKey: Self.key) else { return SystemDockTuckRecord() }
        return try? JSONDecoder().decode(SystemDockTuckRecord.self, from: data)
    }

    /// Returns false when the record could not be encoded; nothing is written in that case.
    @discardableResult
    func save(_ record: SystemDockTuckRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}

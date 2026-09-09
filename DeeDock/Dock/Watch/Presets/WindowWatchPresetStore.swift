import Foundation
import Observation

/// App-lifetime owner for saved watch presets. Edits never start capture or rewrite a running snapshot.
@MainActor @Observable
final class WindowWatchPresetStore {
    private(set) var presets: [WindowWatchPreset] = []
    private(set) var requiresReset = false
    private(set) var error: String?
    @ObservationIgnored private let repository: WindowWatchPresetRepository

    init(repository: WindowWatchPresetRepository = WindowWatchPresetRepository()) {
        self.repository = repository
    }

    func start() {
        do {
            presets = (try repository.load() ?? WindowWatchPresetDocument()).presets
                .map { preset in
                    var next = preset
                    next.configuration = preset.configuration.normalized()
                    return next
                }
                .sorted { $0.updatedAt > $1.updatedAt }
            requiresReset = false
            error = nil
        } catch {
            presets = []
            requiresReset = true
            self.error = String(localized: .watchPresetStorageFailed)
        }
    }

    func preset(_ id: UUID) -> WindowWatchPreset? {
        presets.first { $0.id == id }
    }

    /// Presets whose app hint matches the current window. A match never starts capture or picks a window.
    func suggestions(bundleIdentifier: String?, appName: String) -> [WindowWatchPreset] {
        presets.filter { $0.matching(bundleIdentifier: bundleIdentifier, appName: appName) }
    }

    func others(bundleIdentifier: String?, appName: String) -> [WindowWatchPreset] {
        presets.filter { !$0.matching(bundleIdentifier: bundleIdentifier, appName: appName) }
    }

    @discardableResult
    func save(_ preset: WindowWatchPreset) throws -> WindowWatchPreset {
        guard !requiresReset else { throw CocoaError(.coderReadCorrupt) }
        var next = preset
        next.name = String(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        next.configuration = preset.configuration.normalized()
        next.updatedAt = Date()
        guard next.isValid else { throw CocoaError(.coderInvalidValue) }
        var list = presets.filter { $0.id != next.id }
        if list.count >= WindowWatchPresetDocument.capacity, !presets.contains(where: { $0.id == next.id }) {
            throw CocoaError(.coderInvalidValue)
        }
        list.insert(next, at: 0)
        try commit(list)
        return next
    }

    @discardableResult
    func duplicate(_ id: UUID) throws -> WindowWatchPreset {
        guard let original = preset(id) else { throw CocoaError(.fileNoSuchFile) }
        var copy = original
        copy.id = UUID()
        copy.name = String(localized: .watchPresetCopyName(name: original.name))
        if copy.name.count > 80 { copy.name = String(copy.name.prefix(80)) }
        copy.createdAt = Date()
        return try save(copy)
    }

    func delete(_ id: UUID) throws {
        guard presets.contains(where: { $0.id == id }) else { return }
        try commit(presets.filter { $0.id != id })
    }

    func reset() throws {
        try repository.save(WindowWatchPresetDocument())
        presets = []
        requiresReset = false
        error = nil
    }

    func stop() {}

    private func commit(_ next: [WindowWatchPreset]) throws {
        let document = WindowWatchPresetDocument(presets: next)
        try repository.save(document)
        presets = next
        error = nil
    }
}

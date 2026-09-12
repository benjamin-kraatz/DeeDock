import CoreGraphics
import Foundation
import Observation

/// Owns opt-in and OCR work. Destructive controls invalidate pending recognition before touching disk.
@MainActor @Observable
final class PeekHistoryStore {
    private(set) var enabled: Bool
    private(set) var entries: [PeekHistoryEntry] = []
    private(set) var busy = false
    private(set) var unreadable = false
    private(set) var error: LocalizedStringResource?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let repository: PeekHistoryRepository?
    @ObservationIgnored private let recognizer = PeekHistoryRecognizer()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var control: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private static let enabledKey = "peekHistory.enabled.v1"

    /// A nil repository/defaults pair creates an inert preview without touching user data.
    init(repository: PeekHistoryRepository?, defaults: UserDefaults? = nil) {
        self.repository = repository
        self.defaults = defaults
        enabled = defaults?.bool(forKey: Self.enabledKey) ?? false
        guard let repository else { return }
        busy = true
        control = Task { [weak self] in
            do {
                let entries = try await repository.load()
                guard let self, !Task.isCancelled else { return }
                self.entries = entries
                self.busy = false
            } catch {
                guard let self else { return }
                self.unreadable = true
                self.error = .peekHistoryStorageError
                self.busy = false
                self.enabled = false
                defaults?.set(false, forKey: Self.enabledKey)
            }
        }
    }

    static func live() -> PeekHistoryStore {
        let directory = URL.applicationSupportDirectory.appending(path: "DDock/PeekHistory", directoryHint: .isDirectory)
        return PeekHistoryStore(repository: PeekHistoryRepository(file: directory.appending(path: "index.json")),
                                defaults: .standard)
    }

    /// Capture batches carry this epoch so opting in cannot collect an earlier, unfinished capture.
    var collectionEpoch: UUID? { enabled && !busy && !unreadable ? generation : nil }

    func setEnabled(_ value: Bool) {
        guard !busy, !unreadable else { return }
        invalidateRecognition()
        enabled = value
        defaults?.set(value, forKey: Self.enabledKey)
    }

    /// Only accepted, displayed thumbnail batches enter here. Busy OCR drops new batches instead of queuing images.
    func record(_ cards: [WindowPeekCard], appName: String, epoch captureEpoch: UUID?) {
        guard captureEpoch == generation, enabled, !busy, !unreadable, work == nil,
              CGPreflightScreenCaptureAccess(), let repository else { return }
        let samples = cards.prefix(8).compactMap { card -> (CGImage, String)? in
            guard let image = card.thumbnail else { return nil }
            return (image, String((card.window.title ?? "").prefix(512)))
        }
        guard !samples.isEmpty else { return }
        let epoch = generation
        let date = Date.now
        let name = String(appName.prefix(256))
        work = Task { [weak self, recognizer] in
            defer { self?.work = nil }
            var recognized: [PeekHistoryEntry] = []
            do {
                for (image, title) in samples {
                    let text = try await recognizer.recognize(image)
                    try Task.checkCancellation()
                    if !text.isEmpty {
                        recognized.append(PeekHistoryEntry(id: UUID(), capturedAt: date,
                                                          appName: name, windowTitle: title, text: text))
                    }
                }
                guard let self, generation == epoch, enabled, !Task.isCancelled,
                      CGPreflightScreenCaptureAccess() else { return }
                // Unchanged peeks do not consume retention slots, but a changed text creates a new record.
                var next = PeekHistoryRepository.retained(entries)
                for entry in recognized where !next.contains(where: {
                    $0.appName == entry.appName && $0.windowTitle == entry.windowTitle && $0.text == entry.text
                }) { next.insert(entry, at: 0) }
                next = PeekHistoryRepository.retained(next)
                try Task.checkCancellation()
                try await repository.save(next)
                // A submitted atomic write is committed even if collection was paused while awaiting it.
                // Deletion waits for this task before deriving its replacement document.
                entries = next
                guard generation == epoch, !Task.isCancelled else { return }
                error = nil
            } catch {
                guard let self, generation == epoch, !Task.isCancelled else { return }
                self.error = .peekHistoryCaptureError
            }
        }
    }

    /// A deletion waits for an already-issued write, so an old OCR completion cannot resurrect deleted text.
    func delete(_ id: UUID? = nil) {
        guard !busy else { return }
        let previous = work
        invalidateRecognition()
        busy = true
        control = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let next = id.map { target in PeekHistoryRepository.retained(self.entries.filter { $0.id != target }) } ?? []
            do {
                try await repository?.save(next)
                entries = next
                unreadable = false
                error = nil
            } catch { self.error = .peekHistoryStorageError }
            busy = false
        }
    }

    func results(for query: String) -> [PeekHistoryEntry] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return PeekHistoryRepository.retained(entries).filter { entry in
            let searchable = entry.text + "\n" + entry.appName + "\n" + entry.windowTitle
            return terms.allSatisfy { searchable.localizedStandardContains($0) }
        }
    }

    func stop() {
        invalidateRecognition()
    }

    private func invalidateRecognition() {
        generation = UUID()
        work?.cancel()
    }

    deinit { work?.cancel(); control?.cancel() }
}

import Foundation

/// Silently prepares the current Smart Shelf grouping after persisted Shelf changes.
///
/// The controller owns only speculative work. It never reports an error or changes visible state;
/// opening the Shelf remains the authority for fallback and retry presentation.
@MainActor
final class ShelfSemanticWarmupController {
    typealias RequestProvider = @MainActor @Sendable () async -> SemanticStackRequest?
    typealias Delay = @Sendable () async throws -> Void

    private let organizer: any SemanticStackOrganizing
    private let makeRequest: RequestProvider
    private let delay: Delay
    private let isLowPowerModeEnabled: @Sendable () -> Bool
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(
        organizer: any SemanticStackOrganizing,
        makeRequest: @escaping RequestProvider,
        delay: @escaping Delay = { try await Task.sleep(for: .milliseconds(500)) },
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.organizer = organizer
        self.makeRequest = makeRequest
        self.delay = delay
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    /// Restarts the debounce window. Disabled Smart mode and Low Power Mode cancel current work.
    func schedule(enabled: Bool) {
        cancel()
        guard enabled, !isLowPowerModeEnabled() else { return }
        let token = generation

        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await delay()
                try Task.checkCancellation()
                guard generation == token, !isLowPowerModeEnabled(),
                      await organizer.availability() == .available,
                      let request = await makeRequest(), request.candidates.count >= 4 else { return }
                try Task.checkCancellation()
                guard generation == token else { return }

                let snapshots = await organizer.snapshots(for: request)
                for try await snapshot in snapshots where snapshot.isFinal { return }
            } catch {
                // Warm-up is speculative. The open panel owns user-visible failure and retry UI.
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    func stop() { cancel() }

    /// Test synchronization point for the currently scheduled generation.
    func waitUntilIdle() async {
        await task?.value
    }
}

/// Builds the exact request used by both hidden warm-up and the open Shelf panel.
nonisolated enum ShelfSemanticRequestBuilder {
    static func inputs(
        for items: [ShelfItem],
        accessByID: [UUID: ShelfResourceAccess]
    ) -> [SemanticStackMetadataLoader.Input] {
        items.compactMap { item in
            guard let access = accessByID[item.id] else { return nil }
            return SemanticStackMetadataLoader.Input(
                id: item.id.uuidString,
                name: item.name,
                url: access.url,
                isDirectory: item.isDirectory,
                addedAt: item.addedAt
            )
        }
    }

    static func request(candidates: [SemanticStackCandidate]) -> SemanticStackRequest {
        let locale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return SemanticStackRequest(source: .shelf, candidates: candidates, localeIdentifier: locale)
    }
}

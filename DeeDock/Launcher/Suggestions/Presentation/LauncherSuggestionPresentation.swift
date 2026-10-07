import Foundation
import Observation

/// Owns one frozen ranking and its cancellable request, independently of other display launchers.
@MainActor @Observable
final class LauncherSuggestionPresentation {
    private(set) var snapshot: LauncherSuggestionSnapshot?
    private(set) var availableIDs: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var impressed = false
    #if DEBUG
    @ObservationIgnored private var usesPreviewAvailability = false
    /// Random apps for ``LauncherSuggestionsStore/debugRandomSuggestions``, drawn once per presentation.
    private(set) var debugRandomIDs: [String] = []
    /// Changes on every presentation so the availability task runs again and draws new apps.
    private(set) var debugDraw = 0
    #endif

    /// Runs when discovery or ranking changes, never while evaluating a SwiftUI body.
    func updateAvailability(applications: [LauncherApplication], store: LauncherSuggestionsStore) async {
        #if DEBUG
        if usesPreviewAvailability { return }
        if store.debugRandomSuggestions {
            let ids = Set(applications.map(\.id))
            if debugRandomIDs.isEmpty || !debugRandomIDs.allSatisfy(ids.contains) {
                debugRandomIDs = applications.filter { $0.reference.bundleIdentifier != nil && $0.id != Bundle.main.bundleIdentifier }
                    .shuffled().prefix(3).map(\.id)
            }
            return
        }
        #endif
        guard let snapshot else { availableIDs = []; return }
        let snapshotID = snapshot.id
        let ranked = Set(snapshot.rankedIDs)
        let candidates = applications.filter { ranked.contains($0.id) }
        let existing = await LauncherSuggestionAvailability.existingIDs(candidates)
        guard !Task.isCancelled, self.snapshot?.id == snapshotID else { return }
        availableIDs = existing
    }

    #if DEBUG
    /// Deterministic canvas data; neither discovery nor the filesystem is consulted.
    func installPreview(_ snapshot: LauncherSuggestionSnapshot) {
        end()
        self.snapshot = snapshot
        availableIDs = Set(snapshot.rankedIDs)
        usesPreviewAvailability = true
    }
    #endif

    func begin(store: LauncherSuggestionsStore, foregroundID: String?, modeID: String?) {
        end()
        #if DEBUG
        debugDraw &+= 1
        #endif
        guard let context = store.capture(foregroundID: foregroundID, modeID: modeID) else { return }
        let token = generation
        task = Task { [weak self] in
            let result = await store.predict(context: context)
            guard let self, !Task.isCancelled, generation == token,
                  store.isActive, result?.generation == store.revision else { return }
            snapshot = result
            task = nil
        }
    }

    func recordImpression(store: LauncherSuggestionsStore, appIDs: [String]) {
        guard !impressed, !appIDs.isEmpty, let snapshot, store.isActive,
              snapshot.generation == store.revision else { return }
        impressed = true
        store.recordImpression(snapshot: snapshot, appIDs: appIDs)
    }

    func end() {
        generation = UUID()
        task?.cancel(); task = nil
        snapshot = nil; availableIDs = []; impressed = false
        #if DEBUG
        usesPreviewAvailability = false
        debugRandomIDs = []
        #endif
    }

    func removeUnavailable(_ id: String) { availableIDs.remove(id) }
}

extension LauncherState {
    var suggestionAvailabilityKey: [String] {
        var key = [suggestions.snapshot?.id.uuidString ?? ""]
        #if DEBUG
        key.append("debug|\(catalog.suggestions.debugRandomSuggestions)|\(suggestions.debugDraw)")
        #endif
        return key + library.applications.map { $0.id + "|" + $0.reference.url.path }
    }

    /// Candidates retain snapshot order, while filters and exclusions can remove them immediately.
    var suggestedApplications: [LauncherApplication] {
        let store = catalog.suggestions
        #if DEBUG
        // Random apps carry no snapshot, so they record no impressions or feedback and never
        // touch the learned history.
        if store.debugRandomSuggestions {
            guard query.isEmpty, robiIDs == nil, !usesMixedResults else { return [] }
            let eligible = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return Array(suggestions.debugRandomIDs.compactMap { eligible[$0] }.prefix(suggestionLimit))
        }
        #endif
        guard query.isEmpty, robiIDs == nil, !usesMixedResults, store.isActive,
              let snapshot = suggestions.snapshot, snapshot.generation == store.revision else { return [] }
        let eligible = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        let visibility = suggestionVisibility?() ?? .showAll
        return Array(snapshot.rankedIDs.compactMap { id -> LauncherApplication? in
            guard suggestions.availableIDs.contains(id), let app = eligible[id], app.reference.bundleIdentifier != nil,
                  id != Bundle.main.bundleIdentifier, id != snapshot.context.foregroundID,
                  store.canSuggest(appID: id, snapshot: snapshot) else { return nil }
            if visibility == .hidePinned, pinnedIDs.contains(id) { return nil }
            if visibility == .hideRunning, !pinnedIDs.contains(id), catalog.runningIDs.contains(id) { return nil }
            return app
        }.prefix(suggestionLimit))
    }

    /// At most three, and never more than one row of the full Launcher's grid. The compact grid's
    /// six fixed columns always fit three, and its layout ignores the full Launcher's list setting.
    private var suggestionLimit: Int {
        presentationStyle == .full && layout == .grid ? min(3, max(1, navigationColumns)) : 3
    }

    /// Each visual section begins a row. This keeps vertical navigation aligned across short rows.
    var browseRows: [[LauncherBrowseItem]] {
        let columns = layout == .grid ? max(1, navigationColumns) : 1
        let suggested = suggestedApplications.map { LauncherBrowseItem(id: .suggested($0.id), application: $0) }
        let sections = (suggested.isEmpty ? [] : [suggested]) + groups.map { group in
            group.applications.map { LauncherBrowseItem(id: .application($0.id), application: $0) }
        }
        return sections.flatMap { items in
            stride(from: 0, to: items.count, by: columns).map { offset in
                Array(items[offset..<min(offset + columns, items.count)])
            }
        }
    }

    func suggestionFeedback(_ application: LauncherApplication, kind: LauncherSuggestionFeedback.Kind) {
        guard let snapshot = suggestions.snapshot,
              suggestedApplications.contains(where: { $0.id == application.id }) else { return }
        catalog.suggestions.feedback(appID: application.id, kind: kind, snapshot: snapshot)
    }

    /// Recheck at deliberate activation so a removed bundle cannot keep a stale selectable tile.
    func openSuggested(_ application: LauncherApplication) {
        guard suggestedApplications.contains(where: { $0.id == application.id }) else { return }
        guard catalog.service.resolvedURL(for: application.reference) != nil else {
            suggestions.removeUnavailable(application.id)
            return
        }
        Analytics.track(.launcherSuggestionAccepted(trigger: Analytics.trigger()))
        open(application)
    }

    func recordSuggestionImpression() {
        // Only the full Launcher's morph sets `contentVisible`; the compact popover's content is
        // visible for its whole presentation.
        guard isPresented, presentationStyle == .compact || contentVisible else { return }
        suggestions.recordImpression(store: catalog.suggestions, appIDs: suggestedApplications.map(\.id))
    }
}

/// Discovery can briefly retain a removed bundle. Check only ranked candidates off the UI actor.
nonisolated private enum LauncherSuggestionAvailability {
    @concurrent static func existingIDs(_ applications: [LauncherApplication]) async -> Set<String> {
        var result: Set<String> = []
        for app in applications {
            guard !Task.isCancelled else { return [] }
            if FileManager.default.fileExists(atPath: app.reference.url.path) { result.insert(app.id) }
        }
        return result
    }
}

import AppKit

/// Adapts existing consent and per-display pin owners into a reviewable case. No model output
/// supplies an application identity, file URL, display or mode to the persistence operation.
@MainActor
final class PinJuryContext {
    private let store: DockStore
    private let catalog: ApplicationCatalog
    private let profiles: DisplayProfilesStore
    private let isCurrent: () -> Bool
    private let isCrowded: () -> Bool
    private let canApply: () -> Bool

    init(store: DockStore, catalog: ApplicationCatalog, profiles: DisplayProfilesStore,
         isCurrent: @escaping () -> Bool, isCrowded: @escaping () -> Bool,
         canApply: @escaping () -> Bool) {
        self.store = store; self.catalog = catalog; self.profiles = profiles
        self.isCurrent = isCurrent; self.isCrowded = isCrowded; self.canApply = canApply
    }

    func prepare() -> PinJuryPreparation {
        guard isCurrent(), store.canEditPins else { return .unavailable(.pinJuryStale) }
        guard isCrowded() else { return .unavailable(.pinJuryNotCrowded) }
        guard let evidence = catalog.suggestions.pinJuryEvidence() else {
            return .unavailable(.pinJuryHistoryRequired, needsHistory: true)
        }
        let pins = store.persistedPins
        let pinnedIDs = Set(pins.map(\.id))
        // Only visible linear app pins compete for space. Folders, parked pins, Finder and
        // deliberately hidden pins do not become removal candidates.
        let visibleIDs = Set(store.entries.compactMap { entry -> String? in
            if case .app(let item) = entry { return item.id }
            return nil
        })
        let incumbents = pins.compactMap(\.application).filter { visibleIDs.contains($0.id) && eligible($0) }
        let applications = catalog.launcherLibrary.applications.map(\.reference) + catalog.running
            + observedApplications(evidence: evidence, excluding: pinnedIDs)
        let challengers = applications.filter { !pinnedIDs.contains($0.id) && eligible($0) }
        guard let hearing = PinJuryPolicy.makeCase(pins: incumbents, challengers: challengers, evidence: evidence) else {
            return .unavailable(.pinJuryInsufficientEvidence)
        }
        let modeID = profiles.modes.activeMode.id
        let revision = catalog.suggestions.revision
        let privacyRevision = catalog.suggestions.pinJuryPrivacyRevision
        let exclusions = catalog.suggestions.excludedIDs
        let privacyIsValid = { [self] in
            catalog.suggestions.isActive && catalog.suggestions.revision == revision
                && catalog.suggestions.pinJuryPrivacyRevision == privacyRevision
                && catalog.suggestions.excludedIDs == exclusions
        }
        let isValid = { [self] in
            isCurrent() && isCrowded() && store.canEditPins
                && profiles.modes.activeMode.id == modeID && store.persistedPins == pins
                && eligible(hearing.incumbent.application) && eligible(hearing.challenger.application)
                && store.entries.contains { $0.target == .app(hearing.incumbent.id) }
        }
        return .ready(PinJuryReview(evidence: hearing, privacyIsValid: privacyIsValid, isValid: isValid) { [self] in
            guard privacyIsValid(), isValid(), canApply(),
                  let index = pins.firstIndex(where: { $0.id == hearing.incumbent.id }) else { return false }
            var proposed = pins
            proposed[index] = .application(hearing.challenger.application)
            // Exactly one saved edit, preserving every unrelated pin and its position. Magnetic
            // placement cleanup runs only after successful persistence, never on a failed write.
            guard store.savePins(proposed) else { return false }
            store.willMutateFavoriteIDs?([hearing.incumbent.id, hearing.challenger.id])
            return true
        })
    }

    private func eligible(_ application: ApplicationReference) -> Bool {
        guard application.id != "com.apple.finder", !AppDockPresence.representsCurrentApplication(application),
              !catalog.suggestions.excludedIDs.contains(application.id),
              !store.pinIDsHiddenFromDock.contains(application.id),
              let resolved = catalog.service.resolvedURL(for: application),
              !QuarantineStore.shared.blocks(resolved),
              !QuarantineStore.shared.contains(application.id, url: application.url) else { return false }
        return true
    }

    /// The menu can open before Launcher has discovered installed apps. Resolve a bounded
    /// usage shortlist through Launch Services so a recently quit app can still compete.
    private func observedApplications(evidence: [String: PinJuryEvidence], excluding pinnedIDs: Set<String>) -> [ApplicationReference] {
        let ids = evidence.keys.filter { !pinnedIDs.contains($0) }.sorted {
            let left = PinJuryPolicy.score(evidence[$0]!), right = PinJuryPolicy.score(evidence[$1]!)
            return left == right ? $0 < $1 : left > right
        }
        return ids.prefix(50).compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let bundle = Bundle(url: url), bundle.bundleIdentifier == id else { return nil }
            let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary ?? [:]
            let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            return ApplicationReference(bundleIdentifier: id, url: url, name: name)
        }
    }
}

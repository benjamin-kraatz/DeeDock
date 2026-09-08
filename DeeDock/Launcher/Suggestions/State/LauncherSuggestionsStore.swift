import Foundation
import Observation

/// Owns consent, retained metadata, and privacy epochs. Observation plumbing lives in the
/// catalog. Disk encoding and ranking run outside MainActor and cannot publish across reset.
@MainActor @Observable
final class LauncherSuggestionsStore {
    private(set) var enabled = false
    private(set) var paused = false
    private(set) var excludedIDs: Set<String> = []
    private(set) var promptsEnabled = true
    private(set) var storageUnavailable = false
    private(set) var ready = false
    private(set) var revision = UUID()
    private var promptRevision = 0
    private var revokedAt: [String: Date] = [:]
    var isActive: Bool { enabled && !paused && ready && !storageUnavailable }
    var hasSession: Bool { sessionActive }
    @ObservationIgnored var modeProvider: (() -> String?)?
    @ObservationIgnored var activityChanged: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let repository: LauncherSuggestionsRepository
    @ObservationIgnored private var document = LauncherSuggestionDocument()
    @ObservationIgnored private var recorder = LauncherSuggestionRecorder()
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var latestClock: Date?
    @ObservationIgnored private var timeZone = TimeZone.autoupdatingCurrent.identifier
    @ObservationIgnored private var rankTasks: [UUID: Task<[String], Never>] = [:]
    @ObservationIgnored private var learningGeneration = UUID()
    private static let preferencesKey = "launcher.suggestions.preferences.v1"

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DDock/LauncherSuggestions", isDirectory: true)
    }

    /// Nil directory and defaults are fully isolated from real preferences and user history.
    init(directory: URL? = LauncherSuggestionsStore.defaultDirectory, defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        repository = LauncherSuggestionsRepository(directory: directory)
        if let data = defaults?.data(forKey: Self.preferencesKey) {
            if let settings = try? JSONDecoder().decode(Preferences.self, from: data), settings.version == 1 {
                enabled = settings.enabled; paused = settings.paused
                excludedIDs = Set(settings.excludedIDs.filter(Self.validIdentity))
                promptsEnabled = settings.promptsEnabled
            } else { storageUnavailable = true }
        }
        if directory == nil { ready = true; return }
        let repository = repository
        loadTask = Task { [weak self] in
            do {
                let loaded = try await repository.load()
                guard let self, !Task.isCancelled else { return }
                document = loaded
                let pruned = pruneExcludedContexts()
                promptRevision &+= 1
                ready = true
                if document.expire(now: Date()) || pruned { persist() }
                activityChanged?()
            } catch {
                guard let self, !Task.isCancelled else { return }
                storageUnavailable = true; ready = true
                invalidate()
            }
        }
    }

    func prepare() async { await loadTask?.value }

    func setEnabled(_ value: Bool) {
        guard !value || !storageUnavailable else { return }
        guard value != enabled else { return }
        enabled = value
        invalidate(); savePreferences()
    }

    func setPaused(_ value: Bool) {
        guard value != paused else { return }
        paused = value
        invalidate(); savePreferences()
    }

    func setPromptsEnabled(_ value: Bool) { promptsEnabled = value; savePreferences() }
    func suppressPrompts() { setPromptsEnabled(false) }

    func exclude(appID: String) {
        guard Self.validIdentity(appID) else { return }
        excludedIDs.insert(appID)
        revokedAt[appID] = Date()
        // Remove all effective learning involving the app, including contextual identifiers.
        // Re-enabling suggestions for it starts learning afresh, without restoring old examples.
        pruneExcludedContexts()
        cancelLearning()
        recorder.stop(); sessionActive = false; activityChanged?()
        savePreferences(); persist()
    }

    func include(appID: String) {
        excludedIDs.remove(appID)
        cancelLearning(); savePreferences()
    }

    /// An explicit reset replaces unreadable evidence, cancels loaded/pending work, and leaves
    /// deliberate exclusions and prompt preference intact. Completion failures remain visible.
    func reset() {
        loadTask?.cancel(); loadTask = nil
        document = LauncherSuggestionDocument()
        promptRevision &+= 1
        ready = true; storageUnavailable = false
        invalidate(); savePreferences(); persist()
    }

    func capture(foregroundID: String?, modeID: String?) -> LauncherSuggestionContext? {
        let now = Date()
        maintenance(now: now)
        guard isActive else { return nil }
        let context = recorder.context(now: now, modeID: modeID ?? modeProvider?())
        // The caller supplies the preserved pre-launcher foreground, which is more reliable
        // than querying NSWorkspace after another DDock panel has already taken focus.
        return LauncherSuggestionContext(date: now, foregroundID: eligible(foregroundID) ?? context.foregroundID,
            modeID: context.modeID, recentIDs: context.recentIDs, runningIDs: context.runningIDs,
            hour: context.hour, weekday: context.weekday, foregroundSeconds: context.foregroundSeconds,
            secondsSinceUse: context.secondsSinceUse, secondsSinceTermination: context.secondsSinceTermination)
    }

    func predict(context: LauncherSuggestionContext) async -> LauncherSuggestionSnapshot? {
        let now = Date()
        maintenance(now: now)
        guard isActive else { return nil }
        let epoch = revision
        let learningEpoch = learningGeneration
        let taskID = UUID(), document = document, excluded = excludedIDs
        let task = Task { await LauncherSuggestionBaseline.rank(context: context, document: document, excluded: excluded, now: now) }
        rankTasks[taskID] = task
        let ids = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        rankTasks[taskID] = nil
        guard !Task.isCancelled, !task.isCancelled, isActive, revision == epoch,
              learningGeneration == learningEpoch else { return nil }
        return LauncherSuggestionSnapshot(context: context, modelVersion: LauncherSuggestionBaseline.version,
            rankedIDs: ids.filter { eligible($0) != nil }, createdAt: now, generation: epoch)
    }

    func feedback(appID: String, kind: LauncherSuggestionFeedback.Kind, snapshot: LauncherSuggestionSnapshot) {
        let now = Date()
        maintenance(now: now)
        guard canSuggest(appID: appID, snapshot: snapshot), contextIsEligible(snapshot.context) else { return }
        document.feedback.append(.init(date: now, appID: appID, kind: kind, context: snapshot.context, modelVersion: snapshot.modelVersion))
        persist()
    }

    func recordImpression(snapshot: LauncherSuggestionSnapshot, appIDs: [String]) {
        let now = Date()
        maintenance(now: now)
        guard accepts(snapshot), contextIsEligible(snapshot.context), !document.impressions.contains(where: { $0.id == snapshot.id }) else { return }
        let ids = appIDs.filter { canSuggest(appID: $0, snapshot: snapshot) }
        guard !ids.isEmpty else { return }
        document.impressions.append(.init(id: snapshot.id, date: now, appIDs: ids, context: snapshot.context, modelVersion: snapshot.modelVersion))
        promptRevision &+= 1
        persist()
    }

    var shouldPrompt: Bool {
        _ = promptRevision
        guard isActive, promptsEnabled, document.impressions.count >= 10,
              let first = document.impressions.first?.date, Date().timeIntervalSince(first) >= 7 * 86400 else { return false }
        return document.promptAnswers.last.map { Date().timeIntervalSince($0.date) >= 30 * 86400 } ?? true
    }

    /// Section-level answers measure aggregate quality only; no app receives a negative label.
    func answerPrompt(_ useful: Bool?) {
        guard isActive else { return }
        document.promptAnswers.append(.init(date: Date(), useful: useful))
        promptRevision &+= 1; persist()
    }

    func beginSession(foregroundID: String?, runningIDs: [String], now: Date = Date()) {
        maintenance(now: now)
        guard isActive else { return }
        sessionActive = true
        recorder.begin(now: now, foregroundID: eligible(foregroundID), runningIDs: runningIDs.compactMap(eligible))
        recordEvent(.sessionStart, appID: nil, now: now)
    }

    func endSession(now: Date = Date()) {
        if isActive && sessionActive { recordEvent(.sessionEnd, appID: nil, now: now) }
        recorder.stop(); sessionActive = false
    }

    func observeLaunch(appID: String, runningIDs: [String], now: Date = Date()) {
        guard isActive, sessionActive, let id = eligible(appID) else { return }
        recordEvent(.launch, appID: id, now: now)
        recorder.launched(id, running: runningIDs.compactMap(eligible))
    }

    func observeTermination(appID: String, runningIDs: [String], now: Date = Date()) {
        guard isActive, sessionActive, let id = eligible(appID) else { return }
        guard !runningIDs.contains(id) else { return }
        recordEvent(.termination, appID: id, now: now)
        recorder.terminated(id, now: now, running: runningIDs.compactMap(eligible))
    }

    func observeActivation(appID: String?, now: Date = Date()) {
        guard isActive, sessionActive else { return }
        if let appID, excludedIDs.contains(appID) { endSession(now: now); return }
        recorder.activate(eligible(appID), now: now, modeID: modeProvider?())
    }

    func settleActivation(now: Date = Date()) {
        guard isActive, sessionActive, let example = recorder.settle(now: now), eligible(example.targetID) != nil else { return }
        document.examples.append(example)
        document.events.append(.init(date: now, kind: .activation, appID: example.targetID, context: example.context))
        persist()
    }

    /// Runs at startup, before prediction, and on a low-frequency lifecycle timer even while
    /// disabled. It performs retention cleanup only; off/paused states never collect events.
    func maintenance(now: Date = Date()) {
        guard ready, !storageUnavailable else { return }
        let zone = TimeZone.autoupdatingCurrent.identifier
        if let latestClock, now < latestClock || now.timeIntervalSince(latestClock) > 120 || zone != timeZone {
            recorder.stop(); sessionActive = false
        }
        latestClock = now; timeZone = zone
        promptRevision &+= 1
        revokedAt = revokedAt.filter { now.timeIntervalSince($0.value) < LauncherSuggestionDocument.retention }
        if document.expire(now: now) { invalidate(); persist() }
    }

    func stop() {
        endSession()
        rankTasks.values.forEach { $0.cancel() }; rankTasks.removeAll()
        activityChanged = nil
    }

    /// Awaitable durability boundary for scoped tests and application teardown diagnostics.
    func flush() async { await saveTask?.value }

    private func recordEvent(_ kind: LauncherSuggestionEvent.Kind, appID: String?, now: Date) {
        document.events.append(.init(date: now, kind: kind, appID: appID, context: recorder.context(now: now, modeID: modeProvider?())))
        persist()
    }

    private func accepts(_ snapshot: LauncherSuggestionSnapshot) -> Bool {
        isActive && revision == snapshot.generation && snapshot.createdAt > Date().addingTimeInterval(-LauncherSuggestionDocument.retention)
    }

    /// Exclusion removes only this candidate from a frozen presentation. Reversing the setting
    /// allows future predictions but cannot revive its earlier presentation or feedback.
    func canSuggest(appID: String, snapshot: LauncherSuggestionSnapshot) -> Bool {
        accepts(snapshot) && eligible(appID) != nil && snapshot.rankedIDs.contains(appID)
            && (revokedAt[appID].map { snapshot.createdAt > $0 } ?? true)
    }

    private func contextIsEligible(_ context: LauncherSuggestionContext) -> Bool {
        !excludedIDs.contains { contains($0, in: context) }
            && !revokedAt.contains { $0.value >= context.date && contains($0.key, in: context) }
    }

    @discardableResult private func pruneExcludedContexts() -> Bool {
        guard !excludedIDs.isEmpty else { return false }
        let counts = [document.events.count, document.examples.count, document.feedback.count, document.impressions.count]
        document.events.removeAll { item in
            item.appID.map(excludedIDs.contains) == true || !contextIsEligible(item.context)
        }
        document.examples.removeAll { excludedIDs.contains($0.targetID) || !contextIsEligible($0.context) }
        document.feedback.removeAll { excludedIDs.contains($0.appID) || !contextIsEligible($0.context) }
        document.impressions.removeAll { !excludedIDs.isDisjoint(with: $0.appIDs) || !contextIsEligible($0.context) }
        return counts != [document.events.count, document.examples.count, document.feedback.count, document.impressions.count]
    }

    private func eligible(_ id: String?) -> String? {
        guard let id, Self.validIdentity(id), id != Bundle.main.bundleIdentifier, !excludedIDs.contains(id) else { return nil }
        return id
    }

    nonisolated private static func validIdentity(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 256 && !id.contains("/") && !id.contains(":")
    }

    private func contains(_ id: String, in context: LauncherSuggestionContext) -> Bool {
        context.foregroundID == id || context.recentIDs.contains(id) || context.runningIDs.contains(id)
            || context.secondsSinceUse[id] != nil || context.secondsSinceTermination[id] != nil
    }

    private func invalidate() {
        revision = UUID()
        recorder.stop(); sessionActive = false
        cancelLearning()
        activityChanged?()
    }

    private func cancelLearning() {
        learningGeneration = UUID()
        rankTasks.values.forEach { $0.cancel() }; rankTasks.removeAll()
    }

    private func persist() {
        guard ready, !storageUnavailable else { return }
        if document.expire(now: Date()) {
            revision = UUID(); cancelLearning()
        }
        sequence &+= 1
        let sequence = sequence, snapshot = document, repository = repository
        // Cancel work not yet submitted to disk; the serial repository rejects an older write
        // if it arrives after reset. In-progress atomic writes complete before the next write.
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let retained = try await repository.save(snapshot, sequence: sequence)
                guard let self, self.sequence == sequence else { return }
                if retained.events.count != document.events.count || retained.examples.count != document.examples.count
                    || retained.feedback.count != document.feedback.count || retained.impressions.count != document.impressions.count {
                    document = retained
                    revision = UUID(); cancelLearning()
                }
            } catch is CancellationError { }
            catch {
                guard let self, self.sequence == sequence else { return }
                storageUnavailable = true; invalidate()
            }
        }
    }

    private func savePreferences() {
        let settings = Preferences(enabled: enabled, paused: paused, excludedIDs: excludedIDs.sorted(), promptsEnabled: promptsEnabled)
        if let data = try? JSONEncoder().encode(settings) { defaults?.set(data, forKey: Self.preferencesKey) }
    }

    private struct Preferences: Codable {
        var version = 1
        var enabled: Bool
        var paused: Bool
        var excludedIDs: [String]
        var promptsEnabled: Bool
    }
}

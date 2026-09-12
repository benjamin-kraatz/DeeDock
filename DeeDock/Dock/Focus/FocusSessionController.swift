import AppKit
import Observation

/// One persisted timer across displays, with a deadline task and an optional three-second celebration.
@MainActor @Observable
final class FocusSessionController {
    private(set) var document = FocusSessionsDocument()
    private(set) var requiresReset = false
    private(set) var celebrationID: UUID?
    private(set) var bossVictoryID: UUID?
    private(set) var partyIcons: [String: NSImage] = [:]
    var error: String?
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var victoryTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    private static let key = "dock.focus-sessions.v1"

    init(defaults: UserDefaults = .standard, document: FocusSessionsDocument = FocusSessionsDocument()) {
        self.defaults = defaults
        self.document = document
    }
    var session: FocusSession? { document.session }
    var isActive: Bool { session != nil && session?.phase != .completed }
    var bossFight: BossFightConfiguration { document.bossFight ?? BossFightConfiguration() }
    var focusDebt: FocusDebtState { document.focusDebt ?? FocusDebtState() }
    var item: FocusDockItem? {
        session.map { FocusDockItem(session: $0, celebrationID: celebrationID,
                                   bossFightEnabled: bossFight.enabled, bossVictoryID: bossVictoryID) }
    }

    func start() {
        if let stored = defaults.object(forKey: Self.key) {
            do {
                guard let data = stored as? Data else { throw CocoaError(.coderReadCorrupt) }
                let saved = try JSONDecoder().decode(FocusSessionsDocument.self, from: data)
                guard saved.version == 1, (1...180).contains(saved.minutes), saved.session?.isValid != false,
                      saved.bossFight?.isValid != false, saved.focusDebt?.isValid != false else {
                    throw CocoaError(.coderReadCorrupt)
                }
                document = saved
            } catch { requiresReset = true; self.error = String(localized: .focusStorageFailed) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        refreshPartyIcons()
        reconcile(celebrate: false)
    }

    /// Called after the selected Dock Mode has saved and activated successfully.
    func begin(modeID: UUID, name: String) {
        guard !isActive, !requiresReset else { return }
        let duration = Double(document.minutes * 60)
        var next = document
        let id = UUID()
        next.session = FocusSession(id: id, modeID: modeID, modeName: name, duration: duration,
                                    remainingWhenPaused: duration, deadline: Date().addingTimeInterval(duration), phase: .running)
        var debt = focusDebt
        debt.begin(sessionID: id)
        next.focusDebt = debt
        celebrationID = nil
        dismissVictory()
        save(next)
    }
    func pause() {
        guard var session, session.phase == .running else { return }
        let remaining = session.remaining(at: .now)
        guard remaining > 0 else { finish(); return }
        session.remainingWhenPaused = remaining; session.deadline = nil; session.phase = .paused
        setSession(session)
    }
    func resume() {
        guard var session, session.phase == .paused else { return }
        session.deadline = Date().addingTimeInterval(session.remainingWhenPaused); session.phase = .running
        setSession(session)
    }
    func extend() {
        guard var session, session.phase != .completed, session.duration <= 86100 else { return }
        session.duration += 300
        if session.phase == .running { session.deadline = max(session.deadline ?? .now, .now).addingTimeInterval(300) }
        else { session.remainingWhenPaused += 300 }
        setSession(session)
    }
    func finish(celebrate: Bool = true) {
        guard var session, session.phase != .completed, !requiresReset else { return }
        var next = document
        var debt = focusDebt
        // Record against the original phase/deadline, in the same save as completion.
        debt.end(session, at: .now)
        next.focusDebt = debt
        session.phase = .completed; session.deadline = nil; session.remainingWhenPaused = 0
        if celebrate && document.celebrates && !bossFight.enabled { celebrationID = UUID() }
        next.session = session
        save(next)
        if celebrate && bossFight.enabled && !requiresReset { startVictory() }
    }
    func dismiss() {
        guard !requiresReset else { return }
        var next = document
        var debt = focusDebt
        if let session { debt.end(session, at: .now) }
        next.focusDebt = debt
        next.session = nil
        celebrationID = nil; dismissVictory()
        save(next)
    }

    /// Applies to new sessions only. Turning off immediately clears all meter state without ending the timer.
    func configureFocusDebt(enabled: Bool) {
        guard !requiresReset else { return }
        var next = document
        var debt = focusDebt
        debt.configure(enabled: enabled)
        next.focusDebt = debt
        save(next)
    }
    func configure(minutes: Int? = nil, celebrates: Bool? = nil) {
        guard !requiresReset else { return }
        var next = document
        if let minutes { next.minutes = min(180, max(1, minutes)) }
        if let celebrates { next.celebrates = celebrates }
        save(next)
    }
    func reset() {
        requiresReset = false; celebrationID = nil; dismissVictory()
        partyIcons = [:]; save(FocusSessionsDocument())
    }

    /// Changes the skin immediately without replacing the session or its deadline.
    func configureBossFight(enabled: Bool) {
        guard !requiresReset else { return }
        var next = document
        var configuration = bossFight
        configuration.enabled = enabled
        next.bossFight = configuration
        celebrationID = nil
        if !enabled { dismissVictory() }
        save(next)
        refreshPartyIcons()
    }

    /// Resolves only explicitly selected app bundles, outside pointer and rendering paths.
    func addPartyApps(_ urls: [URL]) {
        guard !requiresReset, bossFight.enabled else { return }
        var configuration = bossFight
        for url in urls.prefix(BossFightConfiguration.maximumPartySize) {
            guard configuration.party.count < BossFightConfiguration.maximumPartySize else { break }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier, !id.isEmpty, id.count <= 512,
                  !configuration.party.contains(where: { $0.id == id }) else { continue }
            let name = String(FileManager.default.displayName(atPath: url.path).prefix(512))
            configuration.party.append(BossFightPartyMember(id: id, name: name))
        }
        var next = document; next.bossFight = configuration; save(next)
        refreshPartyIcons()
    }

    func removePartyApp(_ id: String) {
        guard !requiresReset else { return }
        var next = document; var configuration = bossFight
        configuration.party.removeAll { $0.id == id }; next.bossFight = configuration
        save(next); partyIcons[id] = nil
    }

    /// Ends only the ornament; the completed timer and Capsule action remain available.
    func dismissVictory() {
        victoryTask?.cancel(); victoryTask = nil
        bossVictoryID = nil; changed?()
    }

    private func startVictory() {
        dismissVictory()
        let id = UUID()
        bossVictoryID = id; changed?()
        victoryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, bossVictoryID == id else { return }
            dismissVictory()
        }
    }

    private func refreshPartyIcons() {
        partyIcons = [:]
        guard bossFight.enabled else { return }
        for member in bossFight.party {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: member.id) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            partyIcons[member.id] = icon
        }
    }

    private func setSession(_ session: FocusSession?) {
        guard !requiresReset else { return }
        var next = document; next.session = session; save(next)
    }
    private func save(_ next: FocusSessionsDocument) {
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: Self.key)
            document = next; error = nil
            schedule(); changed?()
        } catch { self.error = String(localized: .focusStorageFailed) }
    }
    private func reconcile(celebrate: Bool = true) {
        if let session, session.phase == .running, session.remaining(at: .now) <= 0 { finish(celebrate: celebrate) }
        else { schedule(); changed?() }
    }
    private func schedule() {
        deadlineTask?.cancel(); deadlineTask = nil
        guard let session, session.phase == .running else { return }
        let id = session.id
        let remaining = session.remaining(at: .now)
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self, self.session?.id == id else { return }
            reconcile()
        }
    }
    func stop() {
        victoryTask?.cancel(); victoryTask = nil; bossVictoryID = nil; partyIcons = [:]
        deadlineTask?.cancel(); deadlineTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil; changed = nil
    }
}

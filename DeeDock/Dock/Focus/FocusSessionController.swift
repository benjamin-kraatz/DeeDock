import AppKit
import Observation

/// One persisted timer across displays. Only a running deadline owns a scheduled task.
@MainActor @Observable
final class FocusSessionController {
    private(set) var document = FocusSessionsDocument()
    private(set) var requiresReset = false
    private(set) var celebrationID: UUID?
    var error: String?
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    private static let key = "dock.focus-sessions.v1"

    init(defaults: UserDefaults = .standard, document: FocusSessionsDocument = FocusSessionsDocument()) {
        self.defaults = defaults
        self.document = document
    }
    var session: FocusSession? { document.session }
    var isActive: Bool { session != nil && session?.phase != .completed }
    var item: FocusDockItem? { session.map { FocusDockItem(session: $0, celebrationID: celebrationID) } }

    func start() {
        if let stored = defaults.object(forKey: Self.key) {
            do {
                guard let data = stored as? Data else { throw CocoaError(.coderReadCorrupt) }
                let saved = try JSONDecoder().decode(FocusSessionsDocument.self, from: data)
                guard saved.version == 1, (1...180).contains(saved.minutes), saved.session?.isValid != false else {
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
        reconcile(celebrate: false)
    }

    /// Called after the selected Dock Mode has saved and activated successfully.
    func begin(modeID: UUID, name: String) {
        guard !isActive, !requiresReset else { return }
        let duration = Double(document.minutes * 60)
        var next = document
        next.session = FocusSession(id: UUID(), modeID: modeID, modeName: name, duration: duration,
                                    remainingWhenPaused: duration, deadline: Date().addingTimeInterval(duration), phase: .running)
        celebrationID = nil
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
        guard var session, session.phase != .completed else { return }
        session.phase = .completed; session.deadline = nil; session.remainingWhenPaused = 0
        if celebrate && document.celebrates { celebrationID = UUID() }
        setSession(session)
    }
    func dismiss() { celebrationID = nil; setSession(nil) }
    func configure(minutes: Int? = nil, celebrates: Bool? = nil) {
        guard !requiresReset else { return }
        var next = document
        if let minutes { next.minutes = min(180, max(1, minutes)) }
        if let celebrates { next.celebrates = celebrates }
        save(next)
    }
    func reset() { requiresReset = false; celebrationID = nil; save(FocusSessionsDocument()) }

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
        deadlineTask?.cancel(); deadlineTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil; changed = nil
    }
}

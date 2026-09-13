import AppKit
import Observation

/// App-wide opt-in, rarity and presentation ownership. Pin writes remain with DockStore.
@MainActor @Observable
final class CourtController {
    let repository = CourtRepository()
    private(set) var hearing: CourtHearing?
    @ObservationIgnored private var panel: CourtPanelController?
    @ObservationIgnored var synchronize: (() -> Void)?
    var enabled: Bool { repository.document.enabled && !repository.unavailable }

    func setEnabled(_ enabled: Bool) {
        close()
        repository.update {
            $0.enabled = enabled; $0.skippedForever = !enabled
            if !enabled { $0.pinSince.removeAll() }
        }
        if enabled { synchronize?() }
    }

    func clear() { close(); repository.clear() }
    func deleteCharacter(_ id: String) {
        close()
        repository.update { document in
            document.characters.removeValue(forKey: id)
            document.cases.removeAll { $0.participantIDs.contains(id) }
            document.relationships = document.relationships.filter { !$0.key.split(separator: "|").contains(Substring(id)) }
        }
    }

    private func scope(_ display: String, _ mode: String) -> String { "\(display)|\(mode)|" }

    func observePins(_ pins: [DockPin], display: String, mode: String, now: Date = Date()) {
        guard enabled else { return }
        let prefix = scope(display, mode)
        let keys = Set(pins.compactMap(\.application).map { prefix + $0.id })
        let old = repository.document.pinSince
        guard keys.contains(where: { old[$0] == nil }) || old.keys.contains(where: { $0.hasPrefix(prefix) && !keys.contains($0) }) else { return }
        repository.update { document in
            document.pinSince = document.pinSince.filter { !$0.key.hasPrefix(prefix) || keys.contains($0.key) }
            for key in keys where document.pinSince[key] == nil { document.pinSince[key] = now }
        }
    }

    /// Snapshot age before removal, because profile observers reconcile synchronously during the save.
    func pinDate(appID: String, display: String, mode: String) -> Date? {
        repository.document.pinSince[scope(display, mode) + appID]
    }

    func removed(app: ApplicationReference, since: Date?, candidates: [ApplicationReference], usage: CourtUsage?,
                 origin: CGPoint, valid: @escaping () -> Bool, usageValid: @escaping () -> Bool,
                 restore: @escaping () -> Bool) {
        let now = Date()
        guard enabled, hearing == nil, CourtComposer.available, valid(), usageValid(), !Self.fullScreen(at: origin) else { return }
        let oldEnough = since.map { $0 <= now && now.timeIntervalSince($0) >= 14 * 86400 } ?? false
        guard oldEnough || usage?.qualifies == true else { return }
        if let previous = repository.document.lastHearing, now.timeIntervalSince(previous) < 7 * 86400 { return }
        let witness = Int.random(in: 0..<100) < 30 ? selectWitness(for: app, candidates: candidates) : nil
        repository.update { $0.lastHearing = now }
        let session = CourtHearing(app: app, witness: witness, repository: repository, sample: false, usage: usage)
        session.contextValid = valid; session.usageValid = usageValid
        session.restore = restore; session.canRestore = true
        present(session, origin: origin)
    }

    private func selectWitness(for app: ApplicationReference, candidates: [ApplicationReference]) -> ApplicationReference? {
        candidates.filter { $0.id != app.id }.sorted { lhs, rhs in
            let a = repository.document.characters[lhs.id], b = repository.document.characters[rhs.id]
            let relatedA = a?.relatedAppID == app.id || repository.document.characters[app.id]?.relatedAppID == lhs.id
                || repository.document.relationships[[app.id, lhs.id].sorted().joined(separator: "|")] != nil
            let relatedB = b?.relatedAppID == app.id || repository.document.characters[app.id]?.relatedAppID == rhs.id
                || repository.document.relationships[[app.id, rhs.id].sorted().joined(separator: "|")] != nil
            if relatedA != relatedB { return relatedA }
            let dateA = a?.lastAppearance ?? .distantPast, dateB = b?.lastAppearance ?? .distantPast
            return dateA == dateB ? lhs.id < rhs.id : dateA < dateB
        }.first
    }

    func sample(witness: Bool) {
        close()
        guard CourtComposer.available else { return }
        let app = ApplicationReference(bundleIdentifier: "court.sample.client", url: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), name: "Quill")
        let other = ApplicationReference(bundleIdentifier: "court.sample.witness", url: URL(fileURLWithPath: "/System/Applications/Preview.app"), name: "Prism")
        let session = CourtHearing(app: app, witness: witness ? other : nil, repository: CourtRepository(defaults: nil), sample: true, usage: nil)
        present(session, origin: NSEvent.mouseLocation)
    }

    private func present(_ session: CourtHearing, origin: CGPoint) {
        hearing = session
        session.close = { [weak self] in self?.close() }
        session.skip = { [weak self] in self?.setEnabled(false) }
        panel = CourtPanelController(hearing: session, origin: origin)
        panel?.show()
        session.start()
    }

    func validateContext() {
        guard let hearing else { return }
        if !hearing.contextValid() || !hearing.usageValid() { close() }
    }

    func close() {
        hearing?.cancel(); panel?.close(); panel = nil; hearing = nil
    }

    /// A conservative permission-free bounds check; no window titles or pixels are collected.
    private static func fullScreen(at point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        let frame = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) != Int(getpid()),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
            return bounds.insetBy(dx: -1, dy: -1).contains(frame)
        }
    }
}

import AppKit
import Observation

/// One bounded hearing. Retry resumes the failed phase with the same cast and completed turns.
@MainActor @Observable
final class CourtHearing {
    let app: ApplicationReference
    let witnessApp: ApplicationReference?
    let sample: Bool
    let repository: CourtRepository
    private(set) var characters: [CourtCharacter] = []
    private(set) var turns: [CourtTurn] = []
    private(set) var partial = ""
    private(set) var generating = false
    private var previewOnly = false
    private(set) var status: LocalizedStringResource = .courtWritingLore
    private(set) var role: CourtRole = .judge
    private(set) var failed = false
    private(set) var finished = false
    private(set) var witnessReady = false
    var paused = false
    var canRestore = false
    var restore: (() -> Bool)?
    var close: (() -> Void)?
    var skip: (() -> Void)?
    var contextValid: () -> Bool = { true }
    var usageValid: () -> Bool = { true }
    var move: ((CGFloat, CGFloat) -> Void)?
    var beginDrag: ((NSEvent) -> Void)?
    var usage: CourtUsage?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var outline: String?
    @ObservationIgnored private var advanceRequested = false
    @ObservationIgnored private var waiting: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var delay: Task<Void, Never>?
    @ObservationIgnored private var witnessAttempted = false
    private let caseID = UUID()
    private var witnessRelationship = ""

    var speakerName: String {
        switch role {
        case .separation: characters.first?.opposingCounsel ?? String(localized: role.title)
        case .reconciliation: characters.first?.counsel ?? String(localized: role.title)
        case .judge: String(localized: .courtJudgeName)
        case .witness: witnessApp?.name ?? String(localized: role.title)
        }
    }

    init(app: ApplicationReference, witness: ApplicationReference?, repository: CourtRepository, sample: Bool, usage: CourtUsage?) {
        self.app = app; witnessApp = witness; self.repository = repository; self.sample = sample; self.usage = usage
    }

    func start() {
        guard task == nil, !finished, !previewOnly else { return }
        failed = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            do { try await run() }
            catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                failed = true; generating = false; partial = ""; status = .courtGenerationFailed
            }
        }
    }

    func cancel() {
        task?.cancel(); delay?.cancel()
        waiting?.resume(); waiting = nil
    }

    func next() {
        guard waiting != nil else { advanceRequested = true; return }
        delay?.cancel(); waiting?.resume(); waiting = nil
    }

    func togglePause() {
        paused.toggle()
        if paused { delay?.cancel() }
        else if waiting != nil { scheduleAdvance() }
    }

    func pinAgain() {
        guard canRestore, contextValid(), restore?() == true else { return }
        canRestore = false
        close?()
    }

    private func check() throws {
        try Task.checkCancellation()
        guard contextValid(), usageValid(), !repository.unavailable else { throw CourtFailure.contextLost }
    }

    private func loadCharacter(_ id: String, name: String, related: CourtCharacter? = nil) async throws -> CourtCharacter {
        if let character = repository.document.characters[id] { return character }
        let value = try await CourtComposer().character(id: id, name: name, related: related)
        try check()
        repository.update { $0.characters[id] = value }
        return value
    }

    private var script: [(CourtRole, LocalizedStringResource)] {
        var result: [(CourtRole, LocalizedStringResource)] = [
            (.judge, .courtOpening), (.separation, .courtOpening), (.reconciliation, .courtOpening),
            (.separation, .courtEvidence), (.reconciliation, .courtEvidence)
        ]
        if witnessReady {
            result += [(.witness, .courtWitnessCalled), (.reconciliation, .courtQuestioning),
                       (.witness, .courtCrossExamination), (.judge, .courtCredibility)]
        }
        result += [(.separation, .courtCrossExamination), (.reconciliation, .courtCrossExamination),
                   (.judge, .courtEvidence), (.separation, .courtClosing), (.reconciliation, .courtClosing),
                   (.judge, .courtJudgment), (.judge, .courtAdjourned)]
        return result
    }

    private func run() async throws {
        try check()
        if characters.isEmpty {
            status = .courtWritingLore
            let client = try await loadCharacter(app.id, name: app.name)
            let judge = try await loadCharacter("court.judge", name: String(localized: .courtJudgeName))
            characters = [client, judge]
        }
        if !witnessAttempted, let witnessApp {
            status = .courtPreparingWitness
            do {
                let witness = try await loadCharacter(witnessApp.id, name: witnessApp.name, related: characters[0])
                let key = [app.id, witness.id].sorted().joined(separator: "|")
                if let relationship = repository.document.relationships[key] {
                    witnessRelationship = relationship
                } else {
                    let relationship = try await CourtComposer().relationship(client: characters[0], witness: witness)
                    try check()
                    repository.update { $0.relationships[key] = relationship }
                    witnessRelationship = relationship
                }
                characters.append(witness); witnessReady = true
                witnessAttempted = true
            } catch {
                try check() // Cancellation/context loss must never become a witness fallback.
                witnessAttempted = true
            }
        }
        if outline == nil {
            status = .courtPreparingCase
            outline = try await CourtComposer().outline(characters: characters, relationship: witnessRelationship, usage: usage,
                history: repository.document.cases.filter { $0.appID == app.id })
            try check()
        }
        let canon = String(decoding: try JSONEncoder().encode(characters), as: UTF8.self)
        let facts = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        let context = "Role mapping: separation is the client opposingCounsel; reconciliation is the client counsel; judge is Judge Dockwell; witness is the third character if present. Witness relationship: \(witnessRelationship)\nCanon: \(canon)\nObserved aggregate counts: \(facts)\nOutline: \(outline ?? "")"
        while turns.count < script.count {
            try check()
            let entry = script[turns.count]
            role = entry.0; status = entry.1; partial = ""; generating = true
            let text = try await CourtComposer().turn(context: context, role: role,
                phase: String(localized: entry.1), previous: turns) { [weak self] text in
                    self?.partial = text
                }
            try check()
            turns.append(CourtTurn(role: role, phase: entry.1, text: text)); partial = ""; generating = false
            if turns.count < script.count { await waitForReading() }
        }
        try check()
        // Only completed hearings contribute continuity. No partially generated testimony is saved.
        let summary = turns.suffix(4).map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        repository.update { document in
            document.cases.append(CourtCaseSummary(id: caseID, appID: app.id, participantIDs: characters.map(\.id), date: Date(), summary: summary))
            if document.cases.count > 100 { document.cases.removeFirst(document.cases.count - 100) }
            for character in characters { document.characters[character.id]?.lastAppearance = Date() }
        }
        finished = true; status = .courtAdjourned
    }

    private func waitForReading() async {
        if advanceRequested { advanceRequested = false; return }
        await withCheckedContinuation { continuation in
            waiting = continuation
            if Task.isCancelled { waiting?.resume(); waiting = nil }
            else if !paused { scheduleAdvance() }
        }
    }

#if DEBUG
    /// Deterministic, inert preview. Retry never starts a real model and storage is isolated.
    static func preview(witness: Bool = false, streaming: Bool = false, error: Bool = false, loading: Bool = false, completed: Bool = false) -> CourtHearing {
        let app = ApplicationReference(bundleIdentifier: "court.preview", url: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), name: "Quill")
        let guest = ApplicationReference(bundleIdentifier: "court.preview.witness", url: URL(fileURLWithPath: "/System/Applications/Preview.app"), name: "Prism")
        let result = CourtHearing(app: app, witness: witness ? guest : nil, repository: CourtRepository(defaults: nil), sample: true, usage: nil)
        result.previewOnly = true
        result.witnessReady = witness
        if !loading {
            result.role = witness ? .witness : .reconciliation
            result.status = witness ? .courtWitnessCalled : .courtClosing
            result.turns = [CourtTurn(role: result.role, phase: result.status,
                text: "I was there when Quill returned the ceremonial ribbon. The court should know it was folded carefully, not abandoned on the courthouse steps.")]
            result.partial = streaming ? "Counsel, that ribbon was the last surviving symbol of our alliance…" : ""
            result.generating = streaming
        }
        result.characters = [CourtCharacter(id: app.id, appName: "Quill, keeper of the ceremonial correspondence",
            biography: "Quill grew up in the courthouse archive, where every promise was written on blue paper. When the ceremonial ribbon vanished, Quill quietly returned it, folded into a perfect square. The incident ended one friendship and began a long correspondence with Prism.",
            counsel: "Ada Ledger", counselBiography: "Ada once catalogued the royal archive. She believes a carefully preserved promise deserves a second hearing.",
            opposingCounsel: "Felix Margin", opposingBiography: "Felix left the archive to defend amicable endings. He has never lost a closing argument about a ribbon.",
            motive: "Protect the dignity of an ending.", incident: "The return of the ceremonial ribbon.",
            relatedAppID: nil, relationship: "Prism witnessed the ribbon's return.")]
        if completed { result.finished = true; result.status = .courtAdjourned }
        if error { result.failed = true; result.status = .courtGenerationFailed }
        return result
    }
#endif

    private func scheduleAdvance() {
        delay?.cancel()
        let seconds = min(18.0, max(4.0, Double(turns.last?.text.count ?? 80) / 18))
        delay = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.waiting?.resume(); self?.waiting = nil
        }
    }
}

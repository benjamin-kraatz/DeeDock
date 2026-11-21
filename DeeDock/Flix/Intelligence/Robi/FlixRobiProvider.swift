import CoreGraphics
import Foundation

/// Ask Robi about files: suggested questions for the selection, and answers streamed from the model
/// Robi's own settings choose.
///
/// Follows Robi's answer model: with Claude chosen, the question and the files go to Claude with the
/// person's key (read from the Keychain only when asked); without a saved key the answer says to add
/// one in Robi's settings. With the on-device model chosen, the answer is made on this Mac. Either
/// way only the selected files are read: at most ``fileLimit``, bounded text from each (less for the
/// on-device model), a picture of images for a model that reads them (Vision text otherwise), and
/// nothing a protected folder DOKK may not read. No tools: Robi can't act from here
/// (`RobiAgent.answer(question:about:model:update:)`), and AI observability gets metadata only.
@MainActor
final class FlixRobiProvider: FlixRobiProviding {
    static let fileLimit = 6
    private let store: RobiStore
    private let services: FlixSmartServices
    private let agent = RobiAgent()

    init(store: RobiStore, services: FlixSmartServices) {
        self.store = store
        self.services = services
    }

    /// Why an answer could not start, as the sheet shows it.
    enum Failure: LocalizedError {
        case needsKey
        case onDeviceUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .needsKey: String(localized: .flixAskRobiNeedsKey)
            case .onDeviceUnavailable(let reason): reason
            }
        }
    }

    var isReady: Bool {
        switch store.settings.answerModel {
        case .claude: true
        case .onDevice: RobiAgent.onDeviceUnavailableReason == nil
        }
    }

    var answersOnDevice: Bool { store.settings.answerModel == .onDevice }

    func questions(for items: [FlixItem]) -> [String] {
        guard !items.isEmpty else { return [] }
        let invoices = items.allSatisfy { item in
            !FlixWords.distinctive(item.name).isDisjoint(with: ["invoice", "rechnung", "receipt", "quittung", "bill"])
                || item.path.flatMap { path in services.analyses[path]?.total } != nil
        }
        if invoices {
            return [String(localized: .flixRobiAskTotal), String(localized: .flixRobiAskDue), String(localized: .flixRobiAskSummarize)]
        }
        let versions = FlixVersionFamilies.groups(items.map {
            FlixVersionFamilies.Member(id: $0.id, name: $0.name, kind: $0.kind, date: $0.date)
        })
        if items.count > 1, !versions.isEmpty {
            return [String(localized: .flixRobiAskChanged), String(localized: .flixRobiAskLatest),
                    String(localized: .flixRobiAskSummarize)]
        }
        if items.allSatisfy({ $0.kind == .image || $0.kind == .screenshot }) {
            return [String(localized: .flixRobiAskWhatsShown), String(localized: .flixRobiAskTextInPicture),
                    String(localized: .flixRobiAskSummarize)]
        }
        return items.count > 1
            ? [String(localized: .flixRobiAskSummarize), String(localized: .flixRobiAskCommon),
               String(localized: .flixRobiAskDraftMessage)]
            : [String(localized: .flixRobiAskSummarize), String(localized: .flixRobiAskImportant),
               String(localized: .flixRobiAskDraftMessage)]
    }

    func answer(_ question: String, about items: [FlixItem]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { return continuation.finish() }
                do {
                    let model = try self.model()
                    let onDevice = if case .onDevice = model { true } else { false }
                    let files = await self.read(Array(items.prefix(Self.fileLimit)), compact: onDevice)
                    try Task.checkCancellation()
                    var sent = ""
                    try await self.agent.answer(question: question, about: files, model: model) { snapshot in
                        // The sheet appends chunks, so only what is new since the last snapshot goes out.
                        let chunk = snapshot.hasPrefix(sent) ? String(snapshot.dropFirst(sent.count)) : "\n\n" + snapshot
                        sent = snapshot
                        if !chunk.isEmpty { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.readable(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func model() throws -> RobiAgent.Model {
        switch store.settings.answerModel {
        case .onDevice:
            if let reason = RobiAgent.onDeviceUnavailableReason { throw Failure.onDeviceUnavailable(String(localized: reason)) }
            return .onDevice
        case .claude:
            guard store.hasClaudeKey, let key = store.claudeKey() else { throw Failure.needsKey }
            return .claude(store.settings.claudeModel, key: key, effort: store.settings.claudeEffort)
        }
    }

    /// The selected files as Robi reads them, bounded per file.
    private func read(_ items: [FlixItem], compact: Bool) async -> [RobiFileContext] {
        let policy = services.readPolicy
        let limit = compact ? 1_500 : 12_000
        var files: [RobiFileContext] = []
        for item in items {
            guard !Task.isCancelled else { break }
            var file = RobiFileContext(name: item.name, kind: Self.kindLabel(item), text: "")
            if let link = item.link {
                file.text = [link.title, link.url.absoluteString].compactMap { $0 }.joined(separator: "\n")
            } else if let path = item.path, policy.canRead(path) {
                if item.kind == .folder {
                    let names = await FlixContentReader.names(in: path, policy: policy).sorted().prefix(60)
                    file.text = names.joined(separator: "\n")
                } else if item.kind != .app {
                    let picture = item.kind == .image || item.kind == .screenshot
                    let content = await FlixContentReader.read(path: path, kind: item.kind,
                                                               contentType: item.contentTypeIdentifier, policy: policy,
                                                               limit: limit,
                                                               wantsPicture: picture, recognizesText: picture && compact)
                    file.text = content?.text ?? ""
                    if let image = content?.image, !compact { file.images = [image] }
                }
            }
            if let caption = item.path.flatMap({ services.analyses[$0]?.caption }) {
                file.text = "Caption: \(caption)\n" + file.text
            }
            files.append(file)
        }
        return files
    }

    private static func kindLabel(_ item: FlixItem) -> String {
        item.fileExtension.isEmpty ? item.kind.rawValue : item.fileExtension
    }

    /// Model errors as Robi words them; others unchanged.
    private static func readable(_ error: Error) -> Error {
        if error is Failure || error is CancellationError { return error }
        return FlixRobiModelError(message: RobiAgent.message(for: error))
    }
}

/// A model error carrying the message Robi shows for it.
private struct FlixRobiModelError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

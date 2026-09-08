import AppKit

/// Serializes explicit Shelf imports across displays and owns cancellation and artifact rollback.
@MainActor
final class ShelfClipboardImporter {
    private let shelf: ShelfController
    private let artifacts: ShelfClipboardArtifacts
    private var task: Task<Void, Never>?
    var isImporting: Bool { task != nil }

    init(shelf: ShelfController, artifacts: ShelfClipboardArtifacts = ShelfClipboardArtifacts()) {
        self.shelf = shelf
        self.artifacts = artifacts
    }

    func paste(from pasteboard: NSPasteboard = .general, report: @escaping (LocalizedStringResource) -> Void) {
        guard task == nil else { return }
        guard !shelf.requiresReset else {
            report(.shelfPasteStorageUnavailable)
            return
        }
        let snapshot: ShelfClipboardSnapshot
        do { snapshot = try ShelfClipboardReader.snapshot(from: pasteboard) }
        catch {
            report(error as? ShelfClipboardFailure == .changed ? .shelfPasteChanged : .shelfPasteUnavailable)
            return
        }
        task = Task { [self] in
            // This task owns the import until any rollback completes, including during shutdown.
            defer { task = nil }
            let failures = await importSnapshot(snapshot)
            if !failures.isEmpty { report(.shelfPasteFailed(details: failures.joined(separator: "\n"))) }
        }
    }

    /// Cancellation does not abandon a file already written. The task finishes rollback before release.
    func stop() { task?.cancel() }

    /// Imports independently so one bad item does not discard valid items in the same batch.
    /// Returns localized failures; successes already reached shared Shelf state through add(_:).
    func importSnapshot(_ snapshot: ShelfClipboardSnapshot) async -> [String] {
        var failures: [String] = []
        if snapshot.omitted > 0 { failures.append(String(localized: .shelfPasteBatchLimit)) }
        for entry in snapshot.entries {
            if Task.isCancelled { break }
            do {
                guard !shelf.requiresReset else {
                    failures.append(String(localized: .shelfPasteStorageUnavailable))
                    break
                }
                switch entry {
                case .invalid:
                    failures.append(String(localized: .shelfPasteUnsupported))
                case .file(let url):
                    let acquired = url.startAccessingSecurityScopedResource()
                    defer { if acquired { url.stopAccessingSecurityScopedResource() } }
                    guard await artifacts.isReadable(url) else {
                        failures.append(String(localized: .shelfPasteFileUnavailable(path: url.path)))
                        continue
                    }
                    try Task.checkCancellation()
                    if try shelf.add([url]) > 0 { throw ShelfClipboardFailure.rejected }
                case .image(let data):
                    guard shelf.items.count < ShelfDocument.capacity else { throw ShelfClipboardFailure.rejected }
                    try await importImage(data)
                }
            } catch is CancellationError { break }
            catch let failure as ShelfClipboardFailure {
                switch failure {
                case .retainedFile(let url):
                    failures.append(String(localized: .shelfPasteRollbackFailed(path: url.path)))
                case .image:
                    failures.append(String(localized: .shelfPasteImageInvalid))
                default:
                    failures.append(String(localized: .shelfPasteRejected))
                }
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        // Keep repeated malformed items from producing an unreadable error panel.
        var seen = Set<String>()
        return failures.filter { seen.insert($0).inserted }
    }

    /// The non-suspending add is the commit boundary. On cancellation or staging failure,
    /// remove only this new image. Successful images remain even if Shelf is subsequently cleared.
    private func importImage(_ data: Data) async throws {
        let url = try await artifacts.write(data)
        do {
            try Task.checkCancellation()
            guard try shelf.add([url]) == 0 else { throw ShelfClipboardFailure.rejected }
        } catch {
            do { try await artifacts.discard(url) }
            catch {
                throw ShelfClipboardFailure.retainedFile(url)
            }
            throw error
        }
    }
}

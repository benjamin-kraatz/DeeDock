import AppKit

/// App-lifetime owner of clipboard collecting, the stored collection, and the museum windows.
///
/// Reads the general pasteboard only while collecting is on, once per change. macOS may show its
/// clipboard privacy prompt on the first read; when the person has set clipboard access to
/// "deny", the controller stops reading instead of retrying. Image analysis and curator labels
/// run after an exhibit is stored, one at a time, and are cancelled on stop.
@MainActor
final class ClipboardMuseumController {
    let store: ClipboardMuseumStore
    private let pasteboard: NSPasteboard
    private let watcher: ClipboardMuseumWatcher
    private let curator = ClipboardCurator()
    private var windowController: ClipboardMuseumWindowController?
    private let slideshow = ClipboardMuseumSlideshowController()
    /// Image encode and analysis, chained so exhibits keep copy order.
    private var imageTask: Task<Void, Never>?
    /// Curator labels, chained so the model runs one request at a time.
    private var curatorTask: Task<Void, Never>?
    private var started = false

    /// Default arguments are evaluated outside the main actor, so the store is built in the body.
    init(store: ClipboardMuseumStore? = nil, pasteboard: NSPasteboard = .general) {
        self.store = store ?? ClipboardMuseumStore()
        self.pasteboard = pasteboard
        watcher = ClipboardMuseumWatcher(pasteboard: pasteboard)
    }

    /// True when macOS is set to always deny DDock clipboard access. Read live, not observed.
    var accessDenied: Bool { pasteboard.accessBehavior == .alwaysDeny }
    /// Whether the on-device model can curate. Read live; the curator UI hides when false.
    var curatorAvailable: Bool { ClipboardCurator.isAvailable }

    func start() {
        guard !started else { return }
        started = true
        store.start()
        watcher.changed = { [weak self] in self?.pasteboardChanged() }
        updateWatcher()
    }

    /// Stops polling and pending work, and closes the windows.
    func stop() {
        watcher.stop()
        watcher.changed = nil
        imageTask?.cancel()
        imageTask = nil
        curatorTask?.cancel()
        curatorTask = nil
        slideshow.stop()
        windowController?.stop()
        started = false
    }

    func setCaptureEnabled(_ enabled: Bool) {
        store.setCaptureEnabled(enabled)
        updateWatcher()
    }

    func reset() {
        imageTask?.cancel()
        imageTask = nil
        curatorTask?.cancel()
        curatorTask = nil
        store.reset()
        updateWatcher()
    }

    /// Opens the museum from an explicit command. Hover never opens it.
    func show(returningTo application: NSRunningApplication?) {
        let windowController = windowController
            ?? ClipboardMuseumWindowController(store: store, actions: actions)
        self.windowController = windowController
        windowController.show(returningTo: application)
    }

    /// Closures the museum views call. Weak, so an open window never keeps the controller alive.
    var actions: ClipboardMuseumActions {
        ClipboardMuseumActions(
            imageURL: { [weak self] in self?.store.imageURL(for: $0) },
            restore: { [weak self] exhibit, revealed in self?.restore(exhibit, revealed: revealed) ?? false },
            redact: { [weak self] in self?.store.redact($0) },
            reveal: { [weak self] id in await self?.reveal(id) },
            unredact: { [weak self] id in await self?.unredact(id) ?? false },
            shred: { [weak self] in self?.store.shred($0) },
            rename: { [weak self] id, title in self?.store.rename(id, to: title) },
            remove: { [weak self] in self?.store.remove($0) },
            clear: { [weak self] in self?.store.clear() },
            save: { [weak self] exhibit, format, revealed, done in self?.save(exhibit, as: format, revealed: revealed, done: done) },
            slideshow: { [weak self] ids, start in self?.playSlideshow(ids, startingAt: start) },
            enableCapture: { [weak self] in self?.setCaptureEnabled(true) })
    }

    /// Puts an exhibit back on the clipboard. A redacted exhibit needs its revealed content, and is
    /// written with the concealed marker so other clipboard histories skip it.
    ///
    /// - Returns: False when the content is unavailable or AppKit refused the write.
    @discardableResult
    func restore(_ exhibit: ClipboardExhibit, revealed: ClipboardVeiledPayload? = nil) -> Bool {
        if exhibit.isRedacted, revealed == nil { return false }
        let text = exhibit.isRedacted ? revealed?.text : exhibit.text
        let item = NSPasteboardItem()
        var objects: [any NSPasteboardWriting] = []
        switch exhibit.kind {
        case .text:
            guard let text else { return false }
            item.setString(text, forType: .string)
            objects = [item]
        case .link:
            guard let text else { return false }
            item.setString(text, forType: .URL)
            item.setString(text, forType: .string)
            objects = [item]
        case .files:
            let urls = (text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL }
            objects = urls
        case .image:
            guard let data = exhibit.isRedacted ? revealed?.image : store.imageData(for: exhibit) else { return false }
            item.setData(data, forType: .png)
            objects = [item]
        }
        guard !objects.isEmpty else { return false }
        if exhibit.isRedacted, objects.first === item {
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        pasteboard.clearContents()
        let written = pasteboard.writeObjects(objects)
        watcher.acknowledgeCurrentChange()
        return written
    }

    private func reveal(_ id: UUID) async -> ClipboardVeiledPayload? {
        guard store.exhibit(id)?.isSealed == true,
              await ClipboardMuseumAuthenticator.authenticate(reason: String(localized: .clipboardMuseumRevealReason))
        else { return nil }
        return store.reveal(id)
    }

    private func unredact(_ id: UUID) async -> Bool {
        guard store.exhibit(id)?.isSealed == true,
              await ClipboardMuseumAuthenticator.authenticate(reason: String(localized: .clipboardMuseumNotSecretReason)),
              store.unredact(id) else { return false }
        curate(id)
        return true
    }

    private func save(_ exhibit: ClipboardExhibit, as format: ClipboardExportFormat,
                      revealed: ClipboardVeiledPayload?, done: @escaping @MainActor (Bool) -> Void) {
        let text = exhibit.isRedacted ? revealed?.text : exhibit.text
        let image = exhibit.isRedacted ? revealed?.image : store.imageData(for: exhibit)
        ClipboardMuseumExporter.save(exhibit, as: format, text: text, imageData: image, completion: done)
    }

    private func playSlideshow(_ ids: [UUID], startingAt start: UUID?) {
        let exhibits = ids.compactMap(store.exhibit).filter { !$0.isRedacted }
        guard !exhibits.isEmpty else { return }
        slideshow.show(exhibits: exhibits, startAt: start, imageURL: { [weak self] in self?.store.imageURL(for: $0) })
    }

    private func updateWatcher() {
        if started, store.captureEnabled, !store.requiresReset {
            watcher.start()
        } else {
            watcher.stop()
        }
    }

    private func pasteboardChanged() {
        guard store.captureEnabled, !store.requiresReset, !accessDenied else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let source = ClipboardSource(name: front?.localizedName, bundleID: front?.bundleIdentifier)
        let date = Date.now
        switch ClipboardMuseumReader.read(from: pasteboard, source: source) {
        case .skipped:
            return
        case .capture(let capture):
            if let exhibit = store.accession(capture, at: date) { curate(exhibit.id) }
        case .image(let data, let source):
            let previous = imageTask
            imageTask = Task { [weak self] in
                await previous?.value
                let encoded = await Task.detached(priority: .utility) { ClipboardImageEncoder.png(from: data) }.value
                guard !Task.isCancelled, let self, let encoded,
                      let exhibit = store.accession(ClipboardCapture(payload: .image(png: encoded.data, width: encoded.width,
                                                                                     height: encoded.height),
                                                                     source: source), at: date) else { return }
                let analysis = await ClipboardImageAnalyzer.analyze(png: encoded.data)
                guard !Task.isCancelled else { return }
                store.applyAnalysis(exhibit.id, analysis)
                curate(exhibit.id)
            }
        }
    }

    /// Queues a curator label. Quietly does nothing when the model is off or unavailable.
    private func curate(_ id: UUID) {
        guard store.curatorEnabled, ClipboardCurator.isAvailable else { return }
        let previous = curatorTask
        curatorTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, let input = store.curatorInput(for: id),
                  let label = await curator.label(for: input), !Task.isCancelled else { return }
            store.applyCuration(id, title: label.title, note: label.note)
        }
    }
}

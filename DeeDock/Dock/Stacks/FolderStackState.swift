import AppKit
import Observation

@MainActor @Observable
final class FolderStackState {
    let folder: FolderReference
    private(set) var entries: [FolderStackEntry] = []
    private(set) var loading = false
    var error: String?
    var presentation: FolderStackPresentation
    var selectedID: String?
    var presentationFocused = false
    var chrome = FolderStackChrome(edge: .bottom, attachment: FolderStackGeometry.idealSize.width / 2)
    @ObservationIgnored var openEntry: ((FolderStackEntryReference) -> Void)?
    @ObservationIgnored var presentationChanged: ((FolderStackPresentation) -> Bool)?
    @ObservationIgnored var dragCompleted: ((Bool) -> Void)?
    @ObservationIgnored private var retryAction: (() -> Void)?
    @ObservationIgnored private var access: FolderResourceAccess?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: FolderDirectoryMonitor?
    @ObservationIgnored private var generation = UUID()

    init(folder: FolderReference, entries: [FolderStackEntry] = [], loading: Bool = false, error: String? = nil) {
        self.folder = folder
        presentation = folder.presentation
        self.entries = entries
        self.loading = loading
        self.error = error
        selectedID = entries.first?.id
    }

    func start() {
        loadTask?.cancel(); loadTask = nil
        monitor?.stop(); monitor = nil
        access = nil
        let access = FolderResourceAccess(folder)
        self.access = access
        guard access.isAvailable else {
            report(String(localized: .folderStackUnavailable)) { [weak self] in self?.start() }
            return
        }
        installMonitor(for: access.url)
        reload()
    }

    func reload() {
        guard let access else { return }
        loadTask?.cancel()
        let token = generation
        loading = true
        error = nil
        retryAction = nil
        loadTask = Task { [weak self] in
            let worker = Task.detached { Result { try FolderStackLoader.contents(of: access) } }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, generation == token else { return }
            loading = false
            switch result {
            case .success(let references):
                entries = references.map { reference in
                    let icon = NSWorkspace.shared.icon(forFile: reference.url.path)
                    icon.size = NSSize(width: 128, height: 128)
                    return FolderStackEntry(reference: reference, icon: icon)
                }
                if self.selectedID == nil || !entries.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = entries.first?.id
                }
            case .failure(let error):
                report(error.localizedDescription) { [weak self] in self?.reload() }
            }
            loadTask = nil
        }
    }

    func choose(_ value: FolderStackPresentation) {
        guard value != presentation else { return }
        let previous = presentation
        presentation = value
        if presentationChanged?(value) != true {
            presentation = previous
            report(String(localized: .folderStackSaveFailed)) { [weak self] in self?.choose(value) }
        }
    }

    func report(_ message: String, retry: @escaping () -> Void) {
        error = message
        retryAction = retry
    }

    func retry() {
        let action = retryAction
        error = nil
        retryAction = nil
        action?()
    }

    func select(by distance: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        selectedID = entries[(current + distance + entries.count) % entries.count].id
    }

    func openSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        openEntry?(entry.reference)
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            self?.reload()
        }
    }

    private func installMonitor(for url: URL) {
        monitor?.stop()
        monitor = FolderDirectoryMonitor(url: url) { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleReload() }
        }
    }

    func stop() {
        generation = UUID()
        loadTask?.cancel(); loadTask = nil
        debounceTask?.cancel(); debounceTask = nil
        monitor?.stop(); monitor = nil
        access = nil
        retryAction = nil
        openEntry = nil; presentationChanged = nil; dragCompleted = nil
    }
}

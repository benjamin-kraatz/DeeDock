import AppKit
import Observation

@MainActor @Observable final class MeltFinderState {
    enum Direction: Int, CaseIterable { case right, left }
    var direction = Direction.right { didSet { plan = nil; completed = 0; message = nil } }
    var locations: [MeltFinderLocation] = []
    var plan: MeltSyncPlan?
    var replacing = false
    var busy = false
    var applying = false
    var completed = 0
    var message: LocalizedStringResource?
    var detail: String?
    var success = 0
    var isPresented = false {
        didSet {
            guard oldValue != isPresented else { return }
            if !isPresented { cancel() }
            visibilityChanged?()
        }
    }
    var isChoosingFolder = false
    @ObservationIgnored weak var presentationWindow: NSWindow?
    @ObservationIgnored var visibilityChanged: (() -> Void)?
    @ObservationIgnored private var folderPicker: NSOpenPanel?
    @ObservationIgnored private var pickerID: UUID?

    @ObservationIgnored private weak var pair: AppMeltPair?
    @ObservationIgnored private let service: AccessibilityApplicationWindowService
    @ObservationIgnored private let finder = MeltFinderAutomation()
    @ObservationIgnored private let sync = MeltFolderSync()
    @ObservationIgnored private var task: Task<Void, Never>?
    private var grants: [URL] = []

    init(pair: AppMeltPair, service: AccessibilityApplicationWindowService) {
        self.pair = pair; self.service = service
    }
    var sourceIndex: Int { direction == .right ? 0 : 1 }
    var destinationIndex: Int { 1 - sourceIndex }
    var actionableCount: Int {
        plan?.entries.filter { $0.kind != .blocked && ($0.kind != .replace || replacing) }.count ?? 0
    }

    func refresh() {
        run {
            self.plan = nil
            self.locations = try await self.currentLocations()
        }
    }

    func preview() {
        run {
            self.plan = nil; self.completed = 0
            self.locations = try await self.currentLocations()
            let preview = try await self.sync.preview(source: self.locations[self.sourceIndex].url,
                destination: self.locations[self.destinationIndex].url)
            try Task.checkCancellation()
            self.plan = preview
        }
    }

    func navigate() {
        run {
            self.plan = nil
            let current = try await self.currentLocations()
            guard current == self.locations else { throw MeltFinderError.changed }
            try await self.finder.navigate(from: current[self.sourceIndex], to: current[self.destinationIndex])
            self.locations = try await self.currentLocations()
            self.message = .meltFinderOpened
            self.success += 1
        }
    }

    func apply() {
        guard let plan, actionableCount > 0 else { return }
        run {
            guard try await self.currentLocations() == self.locations else { throw MeltFinderError.changed }
            self.applying = true; self.completed = 0
            try await self.sync.apply(plan, replacing: self.replacing) { [weak self] count in
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.completed = count
                }
            }
            try Task.checkCancellation()
            self.plan = nil
            self.message = .meltFinderFinished
            self.success += 1
        }
    }

    func hasGrant(_ index: Int) -> Bool {
        guard locations.indices.contains(index) else { return false }
        return grants.contains { canonical($0) == canonical(locations[index].url) }
    }

    /// Keep the pair's interaction hold across the popover → sheet → popover transition.
    /// A sheet avoids runModal's nested event loop and gives the picker an explicit owner.
    func grant(_ index: Int) {
        guard !busy, !isChoosingFolder, let pair, !pair.busy, !pair.isDragging,
              !pair.suspended, locations.indices.contains(index),
              let window = presentationWindow else { return }
        let url = locations[index].url
        let picker = NSOpenPanel()
        picker.canChooseFiles = false; picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false; picker.directoryURL = url
        picker.prompt = String(localized: .meltFinderGrant)
        let id = UUID()
        pickerID = id; folderPicker = picker
        isChoosingFolder = true
        isPresented = false
        visibilityChanged?()
        picker.beginSheetModal(for: window) { [weak self, weak picker] response in
            guard let self, self.pickerID == id else { return }
            if response == .OK, let chosen = picker?.url {
                if self.canonical(chosen) == self.canonical(url) {
                    self.grants.removeAll { self.canonical($0) == self.canonical(chosen) }
                    self.grants.append(chosen)
                    self.message = nil; self.detail = nil
                } else { self.message = .meltFinderChooseExact }
            }
            self.folderPicker = nil; self.pickerID = nil
            // Retain the hold until SwiftUI has had a turn to present the popover again.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, let pair = self.pair, !pair.suspended, !pair.minimized,
                      self.isChoosingFolder, self.presentationWindow != nil else { return }
                self.isPresented = true
                self.isChoosingFolder = false
                self.visibilityChanged?()
            }
        }
    }

    private func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    /// Teardown invalidates the picker callback before closing its sheet, preventing a late reopen.
    func dismiss() {
        pickerID = nil
        folderPicker?.cancel(nil); folderPicker = nil
        isChoosingFolder = false
        isPresented = false
        cancel()
    }

    private func currentLocations() async throws -> [MeltFinderLocation] {
        guard let pair, !pair.suspended, !pair.minimized else { throw MeltFinderError.unavailable }
        var frames: [CGRect] = []
        for token in pair.layoutTokens {
            let window = try await service.meltSummary(token)
            guard let frame = window.frame, !window.isMinimized else { throw MeltFinderError.unavailable }
            frames.append(frame)
        }
        let result = try await finder.locations(frames: frames)
        try Task.checkCancellation()
        return result
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy, let pair, !pair.busy, !pair.isDragging, !pair.suspended else { return }
        busy = true; applying = false; message = nil; detail = nil
        task = Task { [weak self] in
            guard let self else { return }
            let scoped = grants.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                busy = false; applying = false; task = nil
            }
            do { try await operation(); try Task.checkCancellation() }
            catch is CancellationError {
                plan = nil; message = .meltFinderCancelled
            } catch {
                plan = nil
                switch error {
                case MeltFinderError.overlapping: message = .meltFinderOverlap
                case MeltFinderError.changed: message = .meltFinderChanged
                case MeltFinderError.unavailable, MeltFinderError.unsupported: message = .meltFinderUnavailable
                case MeltFinderError.automation(let text): message = .meltFinderAutomation; detail = text
                default: message = .meltFinderFailed; detail = error.localizedDescription
                }
            }
        }
    }

    /// A changed side order invalidates paths and any preview, but keeps explicit folder grants.
    func invalidateLayout() {
        dismiss()
        locations = []; plan = nil; completed = 0; message = nil; detail = nil
    }

    func cancel() { task?.cancel() }
}

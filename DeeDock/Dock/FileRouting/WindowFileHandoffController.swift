import AppKit
import Observation
import SwiftUI

/// One bounded, session-only batch. Status reports requests, never receipt by a destination window.
@MainActor @Observable
final class WindowFileHandoffState {
    let documents: DocumentResourceAccess
    let appName: String
    let windowTitle: String?
    var busy = true
    var valid = false
    var activationAvailable = true
    var openRequested = false
    var status: LocalizedStringResource = .fileRouteChecking
    var failures: [String] = []
    var preview: DockFilePreviewItem?
    @ObservationIgnored var activate: (() -> Void)?
    @ObservationIgnored var open: (() -> Void)?
    @ObservationIgnored var copy: (() -> Void)?
    @ObservationIgnored var close: (() -> Void)?

    init(documents: DocumentResourceAccess, appName: String, windowTitle: String?) {
        self.documents = documents
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

/// Owns retained file grants and the discovery session transferred from Peek until dismissal.
/// Nothing opens or activates on drop. Each outbound operation needs its own explicit action.
@MainActor
final class WindowFileHandoffController: NSObject, NSWindowDelegate {
    nonisolated static let maximumFiles = 100
    private var panel: NSPanel?
    private var state: WindowFileHandoffState?
    private var task: Task<Void, Never>?
    private var actionID: UUID?
    private var discoveryID: UUID?
    private let menus: ApplicationMenuController
    private let applications: any ApplicationServicing
    private var generation = UUID()

    init(menus: ApplicationMenuController, applications: any ApplicationServicing) {
        self.menus = menus
        self.applications = applications
    }

    func show(documents: DocumentResourceAccess, item: DockItem, window: ApplicationWindowSummary?,
              exactWindow: Bool, discoveryID: UUID?, visibleFrame: CGRect) {
        stop()
        self.discoveryID = discoveryID
        let title = window.map {
            ApplicationContextMenuProjection.windowTitle($0, untitled: String(localized: .applicationMenuUntitledWindow))
        }
        let state = WindowFileHandoffState(documents: documents, appName: item.reference.name,
                                           windowTitle: exactWindow ? title : nil)
        self.state = state
        let processes = menus.snapshot(for: item).processes.compactMap {
            NSRunningApplication(processIdentifier: $0.processIdentifier)
        }
        state.activationAvailable = !processes.isEmpty
        state.activate = { [weak self] in
            self?.activate(item, window: exactWindow ? window : nil, processes: processes)
        }
        state.open = { [weak self] in self?.open(item.reference) }
        state.copy = { [weak self] in self?.copyReferences() }
        state.close = { [weak self] in self?.stop() }
        let size = CGSize(width: min(500, visibleFrame.width - 24), height: min(620, visibleFrame.height - 24))
        let panel = NSPanel(contentRect: CGRect(x: visibleFrame.midX - size.width / 2,
                                                y: visibleFrame.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: .fileRouteTitle)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: WindowFileHandoffView(state: state))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        let current = generation
        task = Task { [weak self] in
            let worker = Task.detached { () -> Bool in
                guard documents.urls.count <= Self.maximumFiles else { return false }
                return (try? DockExternalPayload.validateDocuments(documents.urls)) != nil
            }
            let valid = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, current == generation else { return }
            state.busy = false
            state.valid = valid
            state.status = valid ? .fileRouteReady : .fileRouteInvalid
            task = nil
        }
    }

    private func activate(_ item: DockItem, window: ApplicationWindowSummary?, processes: [NSRunningApplication]) {
        guard let state, state.valid, !state.busy, state.activationAvailable else { return }
        if let window {
            state.busy = true
            // AX tokens are single-use. A stale window or lost permission must fail without
            // silently changing this action into activation of an arbitrary app window.
            state.activationAvailable = false
            let current = generation
            actionID = menus.perform(.selectWindow(window.token), for: item) { [weak self] error in
                guard let self, current == generation else { return }
                state.busy = false
                state.status = error ?? .fileRouteActivated
                actionID = nil
            }
        } else {
            guard let app = processes.first(where: { !$0.isTerminated }), app.activate(options: []) else {
                state.activationAvailable = false
                state.status = .fileRouteAppUnavailable
                return
            }
            state.status = .fileRouteActivated
        }
    }

    private func copyReferences() {
        guard let state, state.valid, !state.busy else { return }
        NSPasteboard.general.clearContents()
        let written = NSPasteboard.general.writeObjects(state.documents.urls.map { $0 as NSURL })
        state.status = written ? .fileRouteCopied : .fileRouteCopyFailed
    }

    private func open(_ reference: ApplicationReference) {
        guard let state, state.valid, !state.busy, !state.openRequested else { return }
        state.busy = true
        state.openRequested = true
        let documents = state.documents
        let applications = applications
        let current = generation
        // Submit in source order. Keep every failed filename and continue through independent
        // failures. Never automatically retry files for which Workspace already accepted a request.
        task = Task { [weak self] in
            var submitted = 0
            var failures: [String] = []
            defer { withExtendedLifetime(documents) {} }
            for url in documents.urls {
                guard !Task.isCancelled else { return }
                do {
                    try await applications.openDocuments([url], with: reference)
                    submitted += 1
                } catch {
                    if Task.isCancelled { return }
                    failures.append(String(localized: .fileRouteFileFailed(url.lastPathComponent, error.localizedDescription)))
                }
            }
            guard let self, current == generation else { return }
            state.busy = false
            state.failures = failures
            state.status = .fileRouteOpenResult(submitted, documents.urls.count)
            task = nil
        }
    }

    func windowWillClose(_ notification: Notification) { stop() }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        if let actionID { menus.cancelAction(actionID) }
        actionID = nil
        if let discoveryID { menus.cancelDiscovery(discoveryID) }
        discoveryID = nil
        state?.preview = nil
        state = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

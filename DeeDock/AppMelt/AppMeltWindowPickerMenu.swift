import AppKit

/// Native adapter for the same grouped discovery used by the SwiftUI window picker.
/// Its owner retains discovery through the selected-window handoff after tracking ends.
@MainActor final class AppMeltWindowPickerMenu: NSObject, NSMenuDelegate {
    let state: AppMeltWindowPickerState
    let menu = NSMenu()
    private(set) var isTracking = false
    private(set) var setupRequested = false
    private var started = false
    private(set) var selection: ApplicationWindowSummary?
    private(set) var cancelled = false
    private var windows: [ApplicationWindowSummary] = []

    init(controller: AppMeltController) {
        state = AppMeltWindowPickerState(controller: controller)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        let loading = NSMenuItem(title: String(localized: .applicationMenuWindowsLoading), action: nil, keyEquivalent: "")
        loading.isEnabled = false
        menu.addItem(loading)
        state.discoveryFinished = { [weak self] in self?.populate() }
        addSetupAction()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isTracking = true
        if !started { started = true; state.refresh() }
    }

    func menuDidClose(_ menu: NSMenu) { isTracking = false }

    private func addSetupAction() {
        menu.addItem(.separator())
        let item = NSMenuItem(title: String(localized: .meltSetupMore), action: #selector(openSetup), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func openSetup() { setupRequested = true }

    private func populate() {
        guard !cancelled else { return }
        menu.removeAllItems()
        windows = []
        for group in state.groups {
            let title = state.blockedApps.contains(group.id)
                ? String(localized: .meltReplacementAppInUse(group.name)) : group.name
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for (offset, window) in group.windows.enumerated() {
                let name = window.title.flatMap { $0.isEmpty ? nil : $0 }
                    ?? String(localized: .meltReplacementUntitled(offset + 1))
                let title = state.unavailable.contains(window.token) ? String(localized: .meltReplacementAlreadyPaired(name))
                    : window.isMinimized ? String(localized: .meltReplacementMinimized(name)) : name
                let row = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
                row.target = self
                row.tag = windows.count
                row.isEnabled = !state.unavailable.contains(window.token)
                windows.append(window)
                submenu.addItem(row)
            }
            item.submenu = submenu
            item.isEnabled = !state.blockedApps.contains(group.id)
            menu.addItem(item)
        }
        if state.groups.isEmpty || state.message != nil {
            let message = NSMenuItem(title: String(localized: state.message ?? .meltNoWindows), action: nil, keyEquivalent: "")
            message.isEnabled = false
            menu.addItem(message)
        }
        addSetupAction()
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard !cancelled, windows.indices.contains(sender.tag) else { return }
        selection = windows[sender.tag]
    }

    func cancel() {
        cancelled = true
        menu.cancelTracking()
        state.discoveryFinished = nil
        state.cancel()
    }
}

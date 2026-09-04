import AppKit
import CoreServices
import Observation

/// Owns the shared Finder Trash snapshot and user-initiated Trash operations.
@MainActor @Observable
final class TrashController {
    private(set) var item: TrashDockItem
    @ObservationIgnored var didChange: (() -> Void)?

    @ObservationIgnored private let automation = FinderTrashAutomation()
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init() {
        item = TrashDockItem(state: .unknown, icon: Self.icon(for: .unknown))
    }

    /// Reads Finder state only when the user has already granted Automation access.
    func start() {
        generation = UUID()
        refreshIfAuthorized()
    }

    /// Opens Finder's Trash. Finder owns the protected directory and external-volume Trash.
    func open(completion: @escaping (String?) -> Void) {
        perform({ await $0.open() }, completion: completion)
    }

    /// Moves the complete user-selected batch to Trash and retains its security scopes until completion.
    func recycle(_ access: DocumentResourceAccess, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.recycle(access.urls) { [weak self] moved, error in
            MainActor.assumeIsolated {
                defer { withExtendedLifetime(access) {} }
                if let error {
                    completion(error)
                } else if moved.count != access.urls.count {
                    completion(CocoaError(.fileWriteUnknown))
                } else {
                    self?.setState(.full)
                    completion(nil)
                }
            }
        }
    }

    /// Asks Finder to empty every Trash it owns after DeeDock's explicit confirmation.
    func empty(completion: @escaping (String?) -> Void) {
        perform({ await $0.empty() }, completion: completion)
    }

    /// Performs extra reads around Finder activation so its visible Trash state settles quickly.
    func refreshAfterFinderActivity() {
        let token = generation
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            guard let self else { return }
            for delay in [Duration.milliseconds(300), .seconds(2), .seconds(5)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, generation == token else { return }
                await refreshAuthorizedState()
            }
            self.queryTask = nil
        }
    }

    func stop() {
        generation = UUID()
        queryTask?.cancel()
        queryTask = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        actionTask?.cancel()
        actionTask = nil
        didChange = nil
    }

    private func perform(_ operation: @escaping (FinderTrashAutomation) async -> FinderTrashResult,
                         completion: @escaping (String?) -> Void) {
        guard actionTask == nil else { return }
        let token = generation
        actionTask = Task { [weak self] in
            guard let self else { return }
            let result = await operation(automation)
            guard !Task.isCancelled, generation == token else { return }
            actionTask = nil
            if let count = result.count {
                setState(count == 0 ? .empty : .full)
                startMonitoring()
            }
            completion(result.errorDescription)
        }
    }

    private func refreshIfAuthorized() {
        let token = generation
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            guard let self else { return }
            let count = await automation.itemCountIfAuthorized()
            guard !Task.isCancelled, generation == token else { return }
            self.queryTask = nil
            if let count {
                setState(count == 0 ? .empty : .full)
                startMonitoring()
            }
        }
    }

    /// Finder does not publish a public Trash-change notification. Once Automation access exists,
    /// use a low-frequency serialized read so changes made by Finder or the system Dock stay visible.
    private func startMonitoring() {
        guard monitoringTask == nil else { return }
        let token = generation
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, generation == token {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, generation == token else { return }
                await refreshAuthorizedState()
            }
        }
    }

    private func refreshAuthorizedState() async {
        if let count = await automation.itemCountIfAuthorized() {
            setState(count == 0 ? .empty : .full)
        }
    }

    private func setState(_ state: TrashDockItem.State) {
        let changed = item.state != state
        item = TrashDockItem(state: state, icon: Self.icon(for: state))
        if changed { didChange?() }
    }

    private static func icon(for state: TrashDockItem.State) -> NSImage {
        let named: NSImage? = switch state {
        case .empty: NSImage(named: NSImage.trashEmptyName)
        case .full: NSImage(named: NSImage.trashFullName)
        case .unknown, .unavailable: NSImage(named: NSImage.trashEmptyName)
        }
        let source = named
            ?? NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 128, height: 128))
        let icon = source.copy() as? NSImage ?? source
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }
}

private struct FinderTrashResult: Sendable {
    let count: Int?
    let errorDescription: String?
}

/// Serializes Finder scripting and keeps AppleScript objects off the main actor.
private actor FinderTrashAutomation {
    private static let finderIdentifier = "com.apple.finder"

    func open() -> FinderTrashResult {
        execute("""
        tell application id "com.apple.finder"
            open trash
            activate
            return count of items of trash
        end tell
        """)
    }

    func empty() -> FinderTrashResult {
        execute("""
        tell application id "com.apple.finder"
            empty trash
            return count of items of trash
        end tell
        """)
    }

    func itemCountIfAuthorized() -> Int? {
        guard Self.hasPermissionWithoutPrompt else { return nil }
        return execute("tell application id \"com.apple.finder\" to count items of trash").count
    }

    private func execute(_ source: String) -> FinderTrashResult {
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String
                ?? error[NSAppleScript.errorBriefMessage] as? String
                ?? String(localized: .trashAutomationFailed)
            return FinderTrashResult(count: nil, errorDescription: message)
        }
        return FinderTrashResult(count: descriptor.map { Int($0.int32Value) }, errorDescription: nil)
    }

    private static var hasPermissionWithoutPrompt: Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: finderIdentifier).isEmpty else {
            return false
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: finderIdentifier)
        guard let descriptor = target.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(
            descriptor, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), false
        ) == noErr
    }
}

import AppKit
import CoreServices
import Observation

/// How often DDock asks Finder for the Trash count when nothing more specific has happened.
///
/// Finder publishes no Trash-change notification, and each read is an Apple event that also wakes
/// Finder. Changes usually follow Finder activity, DDock's own Trash actions, or the pointer moving to
/// the dock, and each of those triggers its own read, so the periodic read is only a fallback.
enum TrashRefreshInterval {
    static let standard: Double = 30
    /// Two seconds was the fixed interval before the fallback became event-assisted.
    static let range: ClosedRange<Double> = 2...120
    static let defaultsKey = "debug.trashRefreshInterval"

    /// Release builds always use `standard`. Debug builds honor the value set in Settings.
    static var current: Double {
        #if DEBUG
        let stored = UserDefaults.standard.double(forKey: defaultsKey)
        return stored > 0 ? min(max(stored, range.lowerBound), range.upperBound) : standard
        #else
        standard
        #endif
    }
}

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
    @ObservationIgnored private var lastRead: ContinuousClock.Instant?
    @ObservationIgnored private var attentionTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var intervalObserver: Any?
    @ObservationIgnored private var observedInterval = TrashRefreshInterval.current
    #endif

    init() {
        item = TrashDockItem(state: .unknown, icon: Self.icon(for: .unknown))
    }

    /// Reads Finder state only when the user has already granted Automation access.
    func start() {
        generation = UUID()
        refreshIfAuthorized()
        #if DEBUG
        // Restart the fallback loop when the Debug interval changes, rather than after the old wait.
        intervalObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.intervalMayHaveChanged() }
        }
        #endif
    }

    #if DEBUG
    private func intervalMayHaveChanged() {
        guard observedInterval != TrashRefreshInterval.current else { return }
        observedInterval = TrashRefreshInterval.current
        guard monitoringTask != nil else { return }
        monitoringTask?.cancel(); monitoringTask = nil
        startMonitoring()
    }
    #endif

    /// Reads the count when the pointer reaches a dock, the moment a stale Trash icon would be noticed.
    /// At most one read per few seconds, and only after Automation access is known to exist.
    func refreshForDockAttention() {
        guard monitoringTask != nil, attentionTask == nil else { return }
        if let lastRead, lastRead.duration(to: .now) < .seconds(5) { return }
        let token = generation
        attentionTask = Task { [weak self] in
            guard let self, generation == token else { return }
            await refreshAuthorizedState()
            attentionTask = nil
        }
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
        attentionTask?.cancel()
        attentionTask = nil
        #if DEBUG
        if let intervalObserver { NotificationCenter.default.removeObserver(intervalObserver) }
        intervalObserver = nil
        #endif
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

    /// Finder does not publish a public Trash-change notification. Once Automation access exists, a
    /// serialized fallback read at `TrashRefreshInterval.current` catches changes no event announced,
    /// such as emptying Trash from the system Dock while DDock sits untouched.
    private func startMonitoring() {
        guard monitoringTask == nil else { return }
        let token = generation
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, generation == token {
                try? await Task.sleep(for: .seconds(TrashRefreshInterval.current))
                guard !Task.isCancelled, generation == token else { return }
                await refreshAuthorizedState()
            }
        }
    }

    private func refreshAuthorizedState() async {
        lastRead = .now
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
    /// Reuse the read-only script while monitoring. Recompiling it for every read causes
    /// macOS to repeatedly rescan the same source through XProtect.
    private lazy var countScript = NSAppleScript(source: "tell application id \"com.apple.finder\" to count items of trash")

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
        return execute(countScript).count
    }

    private func execute(_ source: String) -> FinderTrashResult {
        execute(NSAppleScript(source: source))
    }

    private func execute(_ script: NSAppleScript?) -> FinderTrashResult {
        var error: NSDictionary?
        let descriptor = script?.executeAndReturnError(&error)
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

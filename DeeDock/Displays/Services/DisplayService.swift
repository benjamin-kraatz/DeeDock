import AppKit
import ColorSync

/// Owns display/Spaces/wake observation once for the application and publishes fresh geometry.
@MainActor
final class DisplayService {
    var didChange: (([DisplaySnapshot]) -> Void)?
    private var resolver = DisplayIdentityResolver()
    private var names: [UInt32: String] = [:]
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        guard appObservers.isEmpty else { return }
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        }
        refresh()
    }

    func refresh() {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return }
        ids = Array(ids.prefix(Int(count)))
        let screens = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        })
        var uuids: [UInt32: String?] = [:]
        for id in ids {
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
            let value = CFUUIDCreateString(nil, uuid) as String
            uuids[id] = .some(value == "00000000-0000-0000-0000-000000000000" ? nil : value)
            if let screen = screens[id] { names[id] = screen.localizedName }
        }
        let identities = resolver.resolve(uuids)
        let snapshots = ids.compactMap { id -> DisplaySnapshot? in
            guard let identity = identities[id] else { return nil }
            let mirror = CGDisplayMirrorsDisplay(id)
            let screen = screens[id] ?? screens[mirror]
            return DisplaySnapshot(id: identity, runtimeID: id,
                                   name: names[id] ?? String(localized: .displayUnnamed),
                                   isPersistent: identity.hasPrefix("display."), isPrimary: id == CGMainDisplayID(),
                                   frame: screen?.frame ?? .zero, visibleFrame: screen?.visibleFrame ?? .zero,
                                   mirrorSource: mirror == kCGNullDirectDisplay ? nil : mirror,
                                   isDrawable: screens[id] != nil && CGDisplayIsActive(id) != 0)
        }
        names = names.filter { ids.contains($0.key) }
        didChange?(DisplayPolicy.ordered(snapshots))
    }

    func stop() {
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
        didChange = nil
    }
}

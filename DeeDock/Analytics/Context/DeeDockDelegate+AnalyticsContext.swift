import AppKit

extension DeeDockDelegate {
    /// Reads the stores this delegate owns into the plain values the analytics context is built
    /// from. Display names and identifiers are left behind here.
    func analyticsContextInputs() -> AnalyticsContextInputs {
        let profiles = coordinator.profiles
        let scales = Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, Double)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, Double(screen.backingScaleFactor))
        }, uniquingKeysWith: { first, _ in first })
        var inputs = AnalyticsContextInputs()
        inputs.displays = profiles.displays.map { display in
            let store = coordinator.dockStore(for: display.id)
            let pins = profiles.pinLists[display.id] ?? []
            let overrides = profiles.document.profiles[display.id]?.overrides ?? DockSettingsOverrides()
            return AnalyticsContextInputs.Display(
                isMain: display.isPrimary,
                isBuiltIn: CGDisplayIsBuiltin(display.runtimeID) != 0,
                size: display.frame.size,
                scale: scales[display.runtimeID] ?? 1,
                hostsDock: store != nil,
                settings: profiles.effectiveSettings(for: display.id),
                overrideCount: DockSettingField.allCases.count(where: overrides.contains),
                pinnedAppCount: pins.count { $0.application != nil },
                pinnedFolderCount: pins.count { $0.folder != nil },
                runningAppCount: store?.items.count(where: \.isRunning) ?? 0)
        }
        inputs.sharedSettings = profiles.effectiveDefaultSettings
        inputs.modeCount = profiles.modes.modes.count
        inputs.loginItem = loginItems.status
        inputs.accessibility = AnalyticsPermissionStatus(windowAccess.status)
        inputs.screenRecording = AnalyticsPermissionStatus(screenCapture.status)
        inputs.systemDockHidden = SystemDockReservation.reservedEdge(
            in: NSScreen.screens.map { ($0.frame, $0.visibleFrame) }) == nil
        inputs.updates = AnalyticsContextInputs.Updates(
            checksAutomatically: updater.automaticallyChecksForUpdates,
            installsAutomatically: updater.automaticallyInstallsUpdates,
            installsWhenIdle: updater.awareness.installWhenIdle)
        return inputs
    }
}

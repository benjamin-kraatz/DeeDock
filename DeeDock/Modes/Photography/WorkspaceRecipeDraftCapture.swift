import AppKit

extension WorkspaceRecipeDraft {
    /// Called by the sheet's structured task. Uses metadata discovery only, never capture or OCR.
    /// Cancellation must be checked after discovery because ScreenCaptureKit may finish after dismissal.
    func discoverWindows(using service: any WindowContextCapturing) async {
        guard windowStatus == .loading else { return }
        do {
            let windows = try await service.discover()
            try Task.checkCancellation()
            for window in windows {
                // Resolve the still-running owner and reject PID reuse before adding its app identity.
                guard let owner = NSRunningApplication(processIdentifier: window.processIdentifier),
                      owner.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      owner.bundleIdentifier == window.bundleIdentifier,
                      let url = owner.bundleURL else { continue }
                let application = ApplicationReference(bundleIdentifier: owner.bundleIdentifier, url: url,
                                                       name: owner.localizedName ?? window.applicationName)
                addApplication(application, isRunning: true, window: window)
            }
            windowStatus = candidates.contains { !$0.windows.isEmpty } ? .available : .empty
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            switch error as? WindowContextCaptureError {
            case .permissionRequired: windowStatus = .permissionRequired
            case .noWindows: windowStatus = .empty
            default: windowStatus = .unavailable
            }
        }
        selectInitialSteps()
    }
}

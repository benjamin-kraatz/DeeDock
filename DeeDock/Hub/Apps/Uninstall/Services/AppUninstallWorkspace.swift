import AppKit

/// The app-side steps of an uninstall: finding and quitting the app's processes, and moving items DOKK
/// may move itself to the Trash.
@MainActor
enum AppUninstallWorkspace {
    /// What happened to one item DOKK tried to move itself.
    enum RecycleResult: Equatable {
        case moved
        /// macOS refused for lack of permission: App Management for another developer's app, or privacy
        /// protection. Finder may still be able to move it.
        case denied
        case failed
    }

    /// The running processes whose bundle is the app or lives inside it (helpers, login items).
    static func runningApplications(of appURL: URL) -> [NSRunningApplication] {
        let path = appURL.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let bundle = app.bundleURL?.standardizedFileURL.path else { return false }
            return bundle == path || bundle.hasPrefix(path + "/")
        }
    }

    /// Asks the app and its helpers to quit, like ⌘Q, and waits until they're gone.
    ///
    /// The app may ask the user to save changes; that counts toward `timeout`.
    /// - Returns: False if a process is still running when `timeout` ends or the task is cancelled.
    static func quit(_ appURL: URL, timeout: Duration = .seconds(20)) async -> Bool {
        let running = runningApplications(of: appURL)
        for app in running { app.terminate() }
        let deadline = ContinuousClock.now + timeout
        while running.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return true
    }

    /// Moves `url` to the Trash with `NSWorkspace`, which records Put Back.
    static func recycle(_ url: URL) async -> RecycleResult {
        do {
            _ = try await NSWorkspace.shared.recycle([url])
            return FileManager.default.fileExists(atPath: url.path) ? .failed : .moved
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteNoPermissionError { return .denied }
            return AppLeftoverScanner.isPrivacyDenial(error) ? .denied : .failed
        }
    }

    /// Whether only Finder can move `url`: root owns it, or DOKK can't write to its folder (or, for a folder,
    /// to the folder itself, which moving it to another parent requires).
    nonisolated static func needsFinder(_ url: URL) -> Bool {
        let path = url.path
        if let owner = (try? FileManager.default.attributesOfItem(atPath: path))?[.ownerAccountID] as? NSNumber,
           owner.intValue == 0 {
            return true
        }
        if access(url.deletingLastPathComponent().path, W_OK) != 0 { return true }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue && access(path, W_OK) != 0
    }
}

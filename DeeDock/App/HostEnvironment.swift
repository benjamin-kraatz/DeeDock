import Foundation

/// Processes that load DDock's code without being the user's DDock. They must not start live
/// services or read and write the user's saved data.
nonisolated enum HostEnvironment {
    /// Xcode's canvas. Xcode 27's JIT canvas uses the playground flag; older preview hosts use the preview flag.
    static var isPreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    /// `DeeDockTests` runs hosted inside the app. The host shares DDock's bundle identifier and
    /// therefore its preferences domain, so tests must inject their own storage.
    static var isTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}

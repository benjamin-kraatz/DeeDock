import AppKit

/// Whether DOKK may send Finder the read-only Apple Event behind suggestions.
nonisolated enum VaporAutomationPermission: Equatable, Sendable {
    /// Not determined yet. The panel offers "Turn On"; Vapor never asks on its own.
    case undetermined
    case granted
    /// The person said no in the prompt or in System Settings. Suggestions show nothing.
    case denied
    /// Finder isn't running, so macOS can't answer yet.
    case unavailable

    /// Maps `AEDeterminePermissionToAutomateTarget`'s status.
    init(status: OSStatus) {
        switch status {
        case noErr: self = .granted
        case OSStatus(errAEEventWouldRequireUserConsent): self = .undetermined
        case OSStatus(errAEEventNotPermitted): self = .denied
        default: self = .unavailable
        }
    }
}

/// Parses what the Finder script returns: a `file://` URL string, or an empty string for a window
/// without a folder target such as Recents or a search.
nonisolated enum VaporFinderScriptResult {
    static func folderURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty, let url = URL(string: value), url.isFileURL, !url.path.isEmpty else { return nil }
        return url.standardizedFileURL
    }
}

/// Talks to Finder off the main actor. Apple Events block until Finder answers, and the permission
/// request blocks until the person answers the prompt.
actor VaporFinderReader {
    static let finderBundleIdentifier = "com.apple.finder"

    /// Read-only: the URL of the front Finder window's target, or "" when it has none.
    private static let source = """
    tell application id "com.apple.finder"
        if (count of Finder windows) is 0 then return ""
        try
            set t to target of Finder window 1
            if class of t is folder or class of t is disk then return URL of t
        end try
        return ""
    end tell
    """

    private var script: NSAppleScript?

    /// Checks permission. With `ask` false it never shows a prompt; with `ask` true it may.
    func permission(ask: Bool) -> VaporAutomationPermission {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderBundleIdentifier).isEmpty else {
            return .unavailable
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.finderBundleIdentifier)
        guard let descriptor = target.aeDesc else { return .unavailable }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), ask)
        return VaporAutomationPermission(status: status)
    }

    /// The folder shown in Finder's front window, or nil. Call only after permission is granted.
    func frontFolder() throws -> URL? {
        try Task.checkCancellation()
        if script == nil { script = NSAppleScript(source: Self.source) }
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return VaporFinderScriptResult.folderURL(from: result?.stringValue)
    }
}

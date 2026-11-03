import AppKit

/// Decides which entries leave the feed when an application comes to the front.
///
/// Uses the same sender-to-app resolution as the row's Open App: a banner's name counts only
/// when it resolves to exactly one application. Ambiguous and unknown names never match, and
/// system alerts, which name no app, are never cleared this way.
nonisolated enum NotificationFeedAutoClear {
    /// The identity ``ApplicationReference/id`` uses for a running application, or nil when it
    /// has neither a bundle identifier nor a bundle location.
    static func applicationID(of application: NSRunningApplication) -> String? {
        application.bundleIdentifier ?? application.bundleURL?.standardizedFileURL.path
    }

    /// The entries whose sender resolves to the application with `applicationID`.
    ///
    /// - Parameters:
    ///   - entries: The feed's entries.
    ///   - applicationID: The activated application's ``ApplicationReference/id``.
    ///   - resolve: The single application a banner's name refers to, or nil when there is no
    ///     unambiguous match. Called once per distinct name.
    /// - Returns: Matching identifiers in feed order.
    static func entryIDs(in entries: [NotificationFeedEntry], applicationID: String,
                         resolve: (String) -> ApplicationReference?) -> [NotificationFeedEntry.ID] {
        var verdicts: [String: Bool] = [:]
        return entries.compactMap { entry in
            guard let name = entry.appName else { return nil }
            if verdicts[name] == nil { verdicts[name] = resolve(name)?.id == applicationID }
            return verdicts[name] == true ? entry.id : nil
        }
    }
}

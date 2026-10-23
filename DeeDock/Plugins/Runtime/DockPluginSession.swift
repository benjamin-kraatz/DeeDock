import Foundation

/// What a plugin session reports to its owner, always on the main actor.
enum DockPluginSessionEvent {
    case state(DOKKPluginTileState)
    case request(DOKKPluginRequest)
    /// The session is over. `unexpected` is true when the plugin exited, crashed, or never
    /// answered, rather than DOKK letting go.
    case ended(unexpected: Bool)
}

/// One connection to a plugin's process, as ``DockPluginController`` uses it.
///
/// ``DockPluginConnection`` is the ExtensionKit implementation. The protocol lets tests drive the
/// controller with a fake session instead of a real plugin process.
@MainActor
protocol DockPluginSession: AnyObject {
    /// Launches or reaches the plugin and asks for its first tile state.
    func start()
    /// Asks the plugin for its tile state again.
    func refresh()
    /// Tells the plugin about something that happened in DOKK.
    func send(_ event: DOKKPluginHostEvent)
    /// Ends the session on DOKK's side without reporting an event.
    func stop()
}

/// Makes the session for a plugin, or nil when it cannot be reached (it has no identity).
/// The session reports to `onEvent`.
typealias DockPluginSessionFactory = @MainActor (DockPlugin, @escaping (DockPluginSessionEvent) -> Void) -> DockPluginSession?

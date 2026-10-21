import Foundation

/// Exported by the plugin on every connection DOKK opens to it.
///
/// Arguments are JSON from this folder, so the Objective-C shape never changes when a value gains
/// a field. Replies may arrive on any queue.
@objc nonisolated protocol DOKKPluginService {
    /// The first call on a new connection. `hostInfo` is a ``DOKKPluginHostInfo``; the reply is the
    /// plugin's current ``DOKKPluginTileState``.
    func connect(_ hostInfo: Data, reply: @escaping (Data) -> Void)
    /// Replies with the current ``DOKKPluginTileState``.
    func fetchTileState(reply: @escaping (Data) -> Void)
    /// Receives a ``DOKKPluginHostEvent``.
    func handle(_ event: Data)
}

/// Exported by DOKK, called by the plugin without being asked.
@objc nonisolated protocol DOKKPluginHostService {
    /// Receives a new ``DOKKPluginTileState``. Send it on every change; DOKK keeps only the latest.
    func tileStateDidChange(_ state: Data)
    /// Receives a ``DOKKPluginRequest``.
    func perform(_ request: Data)
}

nonisolated extension NSXPCConnection {
    /// Which end of a plugin connection this process is.
    enum DOKKPluginRole {
        /// DOKK: exports ``DOKKPluginHostService`` and calls ``DOKKPluginService``.
        case host
        /// The plugin: exports ``DOKKPluginService`` and calls ``DOKKPluginHostService``.
        case plugin
    }

    /// Sets both interfaces of a plugin connection and the object that serves this end.
    /// Call before `resume()`.
    func configureDOKKPlugin(as role: DOKKPluginRole, exporting exported: AnyObject) {
        let host = NSXPCInterface(with: DOKKPluginHostService.self)
        let plugin = NSXPCInterface(with: DOKKPluginService.self)
        exportedInterface = role == .host ? host : plugin
        remoteObjectInterface = role == .host ? plugin : host
        exportedObject = exported
    }
}

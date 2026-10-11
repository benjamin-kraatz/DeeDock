import Foundation

/// Accepts the host app's connections: each exports the shared index controller and imports the app's status
/// client.
///
/// launchd lets only DOKK.app, the bundle this service is embedded in, look the service up, so the delegate doesn't
/// check the peer again.
final class IndexServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let controller = IndexServiceController.shared
        newConnection.exportedInterface = NSXPCInterface(with: LookoutIndexServing.self)
        newConnection.exportedObject = controller
        newConnection.remoteObjectInterface = NSXPCInterface(with: LookoutIndexClient.self)
        // Interruption doesn't happen on the service side; invalidation means the app is gone.
        // An identifier, not the connection: capturing it would keep it alive, and a weak one may be gone by now.
        let id = ObjectIdentifier(newConnection)
        newConnection.invalidationHandler = { controller.disconnected(id) }
        newConnection.resume()
        controller.connected(newConnection)
        return true
    }
}

let delegate = IndexServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
IndexServiceController.shared.launched()
// Never returns: the service runs until it exits when idle (`IdleExit`) or launchd stops it.
listener.resume()

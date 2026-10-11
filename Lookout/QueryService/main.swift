import Foundation

/// Accepts the host app's connections and exports the shared query encoder on each.
///
/// launchd lets only DOKK.app, the bundle this service is embedded in, look the service up, so the delegate doesn't
/// check the peer again.
final class QueryServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: LookoutQueryServing.self)
        newConnection.exportedObject = QueryEncoderService.shared
        newConnection.resume()
        return true
    }
}

let delegate = QueryServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
// Never returns: the service runs until launchd stops it.
listener.resume()

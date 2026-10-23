import Foundation

/// The object a plugin calls over XPC. Runs on the connection's queue, decodes, and forwards.
///
/// Anything that fails to decode is dropped: an unknown request from a newer plugin, or a payload
/// that is not a contract value at all.
nonisolated final class DockPluginHostEndpoint: NSObject, DOKKPluginHostService {
    private let stateChanged: @Sendable (DOKKPluginTileState) -> Void
    private let requested: @Sendable (DOKKPluginRequest) -> Void

    init(stateChanged: @escaping @Sendable (DOKKPluginTileState) -> Void,
         requested: @escaping @Sendable (DOKKPluginRequest) -> Void) {
        self.stateChanged = stateChanged
        self.requested = requested
    }

    func tileStateDidChange(_ state: Data) {
        guard let state = DOKKPluginTileState.decode(state) else { return }
        stateChanged(state)
    }

    func perform(_ request: Data) {
        guard let request = DOKKPluginRequest.decode(request) else { return }
        requested(request)
    }
}

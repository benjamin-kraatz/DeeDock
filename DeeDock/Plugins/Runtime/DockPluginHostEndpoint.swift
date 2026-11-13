import Foundation

/// The object a plugin calls over XPC. Runs on the connection's queue, decodes, and forwards.
///
/// Anything that fails to decode is dropped: an unknown request from a newer plugin, or a payload
/// that is not a contract value at all. So is anything over ``DOKKPluginContract/maximumMessageBytes``,
/// before it is decoded.
nonisolated final class DockPluginHostEndpoint: NSObject, DOKKPluginHostService {
    private let stateChanged: @Sendable (DOKKPluginTileState) -> Void
    private let requested: @Sendable (DOKKPluginRequest) -> Void

    init(stateChanged: @escaping @Sendable (DOKKPluginTileState) -> Void,
         requested: @escaping @Sendable (DOKKPluginRequest) -> Void) {
        self.stateChanged = stateChanged
        self.requested = requested
    }

    func tileStateDidChange(_ state: Data) {
        guard let state = Self.decodeState(state) else { return }
        stateChanged(state)
    }

    func perform(_ request: Data) {
        guard Self.isWithinLimit(request), let request = DOKKPluginRequest.decode(request) else { return }
        requested(request)
    }

    /// Whether a plugin's message is small enough to decode. A plugin is a third-party process,
    /// so DOKK never spends unbounded memory or time decoding what it sends.
    static func isWithinLimit(_ data: Data) -> Bool {
        data.count <= DOKKPluginContract.maximumMessageBytes
    }

    /// A tile state from a plugin, or nil when it is too large or does not decode. Used for
    /// pushed states and for the replies to `connect` and `fetchTileState`.
    static func decodeState(_ data: Data) -> DOKKPluginTileState? {
        guard isWithinLimit(data) else { return nil }
        return DOKKPluginTileState.decode(data)
    }
}

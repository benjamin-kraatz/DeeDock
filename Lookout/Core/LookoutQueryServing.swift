import Foundation

/// The XPC interface of `LookoutQueryService`, the text-only query encoder embedded in DOKK.app.
///
/// The service loads EmbeddingGemma 2's text model on the first call and keeps it for its lifetime, so the first call
/// after the service launches pays the cold start (about the model load plus two warm-up embeds). Calls run one at a
/// time, in the order they arrive.
///
/// The protocol is `nonisolated` so it stays callable from NSXPC's own queues when the app compiles it with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Replies arrive on an arbitrary queue.
@objc nonisolated protocol LookoutQueryServing {
    /// Embeds each text as given, in order, with no prompt added: callers frame queries with `Prompts.query` (or
    /// `Prompts.codeQuery`) themselves, so the service needn't know which kind of search it serves.
    ///
    /// - Parameters:
    ///   - texts: The framed queries. Each is cut at 512 tokens.
    ///   - reply: On success, the vectors as `QueryVectorRows` data (`texts.count` rows of 768 little-endian Float32,
    ///     each L2-normalized) and a nil error. On failure, nil data and a description of what went wrong, such as a
    ///     missing model file.
    func embedQueries(_ texts: [String], reply: @escaping @Sendable (Data?, String?) -> Void)

    /// Loads the model now, so the next query doesn't wait for it (for example when the search panel opens).
    ///
    /// - Parameter reply: Nil once the model is loaded and warm, or a description of why it couldn't be loaded.
    func warmUp(reply: @escaping @Sendable (String?) -> Void)
}

/// The XPC service names of Lookout's services.
nonisolated enum LookoutServiceNames {
    /// The query service's bundle identifier, which is also its XPC service name: the app's identifier plus
    /// `.LookoutQueryService` (Configuration/LookoutService.xcconfig derives it the same way, so a Debug app embeds
    /// the `.dev` service).
    static func query(appBundleIdentifier: String) -> String {
        "\(appBundleIdentifier).LookoutQueryService"
    }

    /// The index service's XPC service name, derived the same way: the app's identifier plus `.LookoutIndexService`.
    static func index(appBundleIdentifier: String) -> String {
        "\(appBundleIdentifier).LookoutIndexService"
    }
}

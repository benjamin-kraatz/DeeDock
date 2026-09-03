import AppKit

/// Failures specific to an app icon's show/hide toggle.
enum ApplicationPrimaryActionError: Error {
    /// The foreground application rejected the request to hide.
    case hideRejected
}

/// Main-actor OS boundary; injected fakes let lifecycle tests avoid launching real applications.
@MainActor
protocol ApplicationServicing {
    func runningApplications() -> [ApplicationReference]
    func defaultFavorites() -> [ApplicationReference]
    func resolvedURL(for reference: ApplicationReference) -> URL?
    func icon(for url: URL?) -> NSImage
    func pruneIcons(keeping urls: Set<URL>)
    /// Hides the matching foreground app, otherwise opens or activates it.
    func performPrimaryAction(_ reference: ApplicationReference) async throws
    func open(_ reference: ApplicationReference) async throws
    /// Hands the entire user-selected batch to this app; success describes the OS handoff only.
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws
}

import Foundation

/// Why Lookout's model download stopped. `message` is what onboarding shows under the file; `analyticsCategory` is
/// the closed token `lookout_model_download` reports. Neither carries a path or a URL.
nonisolated enum LookoutDownloadError: Error, Equatable, Sendable {
    /// Less free space than the download needs (`LookoutDiskSpace.required`).
    case notEnoughSpace(needed: Int64, available: Int64)
    /// The connection failed (a `URLError` code: offline, timed out, connection lost).
    case network(code: Int)
    /// Hugging Face answered with an HTTP status other than 200 or 206.
    case server(status: Int)
    /// A redirect pointed outside Hugging Face (`LookoutDownloadHosts`), so the download stopped there.
    case unexpectedHost
    /// The whole file arrived but its SHA-256 isn't the pinned one. The partial file is deleted.
    case checksumMismatch
    /// The transfer ended with a different number of bytes than the file has.
    case incomplete
    /// The file couldn't be written or moved into place. `reason` is the system's own localized description.
    case write(reason: String)

    /// A localized sentence for onboarding, with any number or system reason interpolated through the catalog.
    var message: String {
        switch self {
        case .notEnoughSpace(let needed, let available):
            String(localized: .lookoutDownloadErrorSpace(
                needed.formatted(.byteCount(style: .file)), available.formatted(.byteCount(style: .file))))
        case .network:
            String(localized: .lookoutDownloadErrorNetwork)
        case .server(let status):
            String(localized: .lookoutDownloadErrorServer(status))
        case .unexpectedHost:
            String(localized: .lookoutDownloadErrorHost)
        case .checksumMismatch:
            String(localized: .lookoutDownloadErrorChecksum)
        case .incomplete:
            String(localized: .lookoutDownloadErrorIncomplete)
        case .write(let reason):
            String(localized: .lookoutDownloadErrorWrite(reason))
        }
    }

    /// The error's category for analytics.
    var analyticsCategory: AnalyticsLookoutDownloadError {
        switch self {
        case .notEnoughSpace: .diskSpace
        case .network: .network
        case .server: .server
        case .unexpectedHost: .host
        case .checksumMismatch: .checksum
        case .incomplete: .incomplete
        case .write: .write
        }
    }

    /// Sorts an error a transfer threw into a download error. `CancellationError` isn't one: callers check for it
    /// first.
    static func from(_ error: Error) -> LookoutDownloadError {
        if let error = error as? LookoutDownloadError { return error }
        if let error = error as? URLError { return .network(code: error.errorCode) }
        return .write(reason: error.localizedDescription)
    }
}

/// Where model downloads may go: Hugging Face only, over HTTPS. Its `resolve` URLs redirect to its own CDN hosts
/// (`cdn-lfs.hf.co`, `cas-bridge.xethub.hf.co` and the like); a redirect anywhere else ends the download.
nonisolated enum LookoutDownloadHosts {
    static let allowedDomains = ["huggingface.co", "hf.co"]

    static func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

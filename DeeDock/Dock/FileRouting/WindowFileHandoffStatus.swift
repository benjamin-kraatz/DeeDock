import SwiftUI

/// Everything the handoff panel can report about one batch, with the symbol and tone that belong
/// to it.
///
/// The panel used to carry a bare `LocalizedStringResource`, so "references copied" and "the app is
/// gone" arrived as the same grey sentence. Modelling the cases here lets the footer separate
/// progress, success, and failure without a view comparing localized text.
enum WindowFileHandoffStatus {
    /// Validating the batch. Nothing has been opened or activated.
    case checking
    case ready
    /// The whole batch was rejected: missing files, unsupported items, or over the batch limit.
    case invalid
    /// The destination came forward. Activation is not delivery.
    case activated
    case copied
    case copyFailed
    /// The originally chosen process is gone, so its window token can no longer be trusted.
    case appUnavailable
    /// Counts describe accepted Workspace requests, never verified delivery to a window.
    case openResult(submitted: Int, total: Int)
    /// An activation attempt the accessibility layer refused, carrying its own message.
    case actionFailed(LocalizedStringResource)

    /// How reassuring the status is, which decides its color in the footer.
    enum Tone {
        case working, neutral, positive, warning

        var color: Color {
            switch self {
            case .working, .neutral: .secondary
            case .positive: .green
            case .warning: .orange
            }
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .checking: .fileRouteChecking
        case .ready: .fileRouteReady
        case .invalid: .fileRouteInvalid
        case .activated: .fileRouteActivated
        case .copied: .fileRouteCopied
        case .copyFailed: .fileRouteCopyFailed
        case .appUnavailable: .fileRouteAppUnavailable
        case .openResult(let submitted, let total): .fileRouteOpenResult(submitted, total)
        case .actionFailed(let message): message
        }
    }

    var symbol: String {
        switch self {
        case .checking: "hourglass"
        case .ready: "checkmark.circle.fill"
        case .invalid, .copyFailed, .actionFailed: "exclamationmark.triangle.fill"
        case .activated: "arrow.up.forward.app.fill"
        case .copied: "doc.on.clipboard.fill"
        case .appUnavailable: "xmark.octagon.fill"
        case .openResult(let submitted, let total):
            submitted == total ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
    }

    var tone: Tone {
        switch self {
        case .checking: .working
        case .ready, .copied: .positive
        case .activated: .neutral
        case .invalid, .copyFailed, .appUnavailable, .actionFailed: .warning
        case .openResult(let submitted, let total): submitted == total ? .positive : .warning
        }
    }
}

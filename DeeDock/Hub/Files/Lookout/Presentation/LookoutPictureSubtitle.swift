import Foundation

/// The line under the picture's name in the results bar (the mockup's `.qbar .s2`): how the picture was read, or that
/// it's being read. Pure, so every case is testable.
nonisolated enum LookoutPictureSubtitle: Equatable, Sendable {
    /// The picture reader is loading (with a spinner).
    case waking
    /// The picture is being read (with a spinner).
    case reading
    /// Find Similar reused the index's vector: "From your index · Page 7 · instant".
    case fromIndex(page: Int?)
    /// A dropped picture (or one read for Find Similar): "New picture · read in 0.4 s · not saved". Nil seconds when
    /// Lookout can't search yet.
    case new(seconds: Double?)
    /// A pasted picture: "read in 0.4 s · not saved".
    case pasted(seconds: Double?)

    /// Whether the line shows the spinner.
    var isBusy: Bool { self == .waking || self == .reading }

    /// - Parameters:
    ///   - isPasted: The picture came from the pasteboard, not a file.
    ///   - canSearch: Lookout can search (`LookoutPictureContent.canSearch`); otherwise nothing is read.
    ///   - stored: The stored vector Find Similar reused, if it did.
    init(isPasted: Bool, phase: LookoutPictureSearch.Phase, canSearch: Bool, stored: LookoutSimilarSource?,
         readSeconds: Double?) {
        if canSearch, phase == .waking {
            self = .waking
        } else if canSearch, phase == .reading {
            self = .reading
        } else if canSearch, phase == .lookingUp || stored != nil {
            self = .fromIndex(page: stored?.page)
        } else {
            let seconds = canSearch ? readSeconds : nil
            self = isPasted ? .pasted(seconds: seconds) : .new(seconds: seconds)
        }
    }

    /// The localized line. Seconds show with one decimal in the person's number format ("0.4 s", "0,4 s").
    var text: String {
        switch self {
        case .waking: String(localized: .lookoutPictureWaking)
        case .reading: String(localized: .lookoutPictureReading)
        case .fromIndex(let page?): String(localized: .lookoutPictureSubtitleIndexPage(page))
        case .fromIndex(nil): String(localized: .lookoutPictureSubtitleIndex)
        case .new(let seconds?): String(localized: .lookoutPictureSubtitleNew(Self.format(seconds)))
        case .new(nil): String(localized: .lookoutPictureSubtitleNewUnread)
        case .pasted(let seconds?): String(localized: .lookoutPictureSubtitlePasted(Self.format(seconds)))
        case .pasted(nil): String(localized: .lookoutPictureSubtitlePastedUnread)
        }
    }

    static func format(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
    }
}

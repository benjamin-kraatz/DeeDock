import SwiftUI

/// A quiet line above Lookout's results about what may be missing (the mockup's `.empty` notes): files still being
/// read, reading paused and why, or Lookout stopped. Also above the results of a search with a picture.
struct LookoutStatusNote: View {
    let text: String

    init(text: String) {
        self.text = text
    }

    init(notice: LookoutSectionContent.Notice) {
        self.init(text: Self.text(for: notice))
    }

    private static func text(for notice: LookoutSectionContent.Notice) -> String {
        switch notice {
        case .indexing(let remaining?) where remaining > 0: String(localized: .lookoutNoteIndexing(remaining))
        case .indexing: String(localized: .lookoutNoteIndexingUnknown)
        case .paused(let reason): reason.note
        case .failed(let failure): failure.message
        }
    }

    /// The note above the results of a search with a picture: while paused, it says the picture is still read.
    init(pictureNotice notice: LookoutPictureContent.Notice) {
        switch notice {
        case .indexing(let remaining): self.init(notice: .indexing(remaining: remaining))
        case .paused(let reason): self.init(text: reason.pictureNote)
        case .failed(let failure): self.init(notice: .failed(failure))
        }
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The honest empty state (the mockup's `.honest`): Lookout found nothing that clearly fits, and says so rather than
/// showing weak guesses.
struct LookoutHonestEmpty: View {
    /// The sentence; the search by words' by default. A search with a picture says "for this one", or that the
    /// picture couldn't be read.
    var message: LocalizedStringResource = .lookoutEmptyHonest

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(LookoutTheme(scheme).card, in: shape)
            .overlay { shape.strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}

extension LookoutPauseReason {
    /// The note under the Lookout header while reading waits: why, and that what's read stays searchable.
    var note: String {
        switch self {
        case .lowPowerMode: String(localized: .lookoutNotePausedLowPowerMode)
        case .warm: String(localized: .lookoutNotePausedWarm)
        case .onBattery: String(localized: .lookoutNotePausedOnBattery)
        case .user: String(localized: .lookoutNotePausedUser)
        }
    }

    /// The note above the results of a search with a picture while reading waits: the picture is still read.
    var pictureNote: String {
        switch self {
        case .lowPowerMode: String(localized: .lookoutPictureNotePausedLowPowerMode)
        case .warm: String(localized: .lookoutPictureNotePausedWarm)
        case .onBattery: String(localized: .lookoutPictureNotePausedOnBattery)
        case .user: String(localized: .lookoutPictureNotePausedUser)
        }
    }
}

#Preview("Notes") {
    VStack(alignment: .leading, spacing: 0) {
        LookoutStatusNote(notice: .indexing(remaining: 1_204))
        LookoutStatusNote(notice: .indexing(remaining: nil))
        LookoutStatusNote(notice: .paused(.lowPowerMode))
        LookoutStatusNote(notice: .failed(LookoutFailure(kind: .service)))
        LookoutStatusNote(pictureNotice: .paused(.lowPowerMode))
        LookoutHonestEmpty()
        LookoutHonestEmpty(message: .lookoutPictureHonest)
    }
    .frame(width: 560)
    .padding()
    .background(.regularMaterial)
}

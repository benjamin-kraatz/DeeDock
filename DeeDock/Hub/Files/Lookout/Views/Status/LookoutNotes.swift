import SwiftUI

/// A quiet line above Lookout's results about what may be missing (the mockup's `.empty` notes): files still being
/// read, reading paused and why, or Lookout stopped.
struct LookoutStatusNote: View {
    let notice: LookoutSectionContent.Notice

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: String {
        switch notice {
        case .indexing(let remaining?) where remaining > 0: String(localized: .lookoutNoteIndexing(remaining))
        case .indexing: String(localized: .lookoutNoteIndexingUnknown)
        case .paused(let reason): reason.note
        case .failed(let failure): failure.message
        }
    }
}

/// The honest empty state (the mockup's `.honest`): Lookout found nothing that clearly fits, and says so rather than
/// showing weak guesses.
struct LookoutHonestEmpty: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text(.lookoutEmptyHonest)
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
}

#Preview("Notes") {
    VStack(alignment: .leading, spacing: 0) {
        LookoutStatusNote(notice: .indexing(remaining: 1_204))
        LookoutStatusNote(notice: .indexing(remaining: nil))
        LookoutStatusNote(notice: .paused(.lowPowerMode))
        LookoutStatusNote(notice: .failed(LookoutFailure(kind: .service)))
        LookoutHonestEmpty()
    }
    .frame(width: 560)
    .padding()
    .background(.regularMaterial)
}

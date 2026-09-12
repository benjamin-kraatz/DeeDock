import SwiftUI

/// Shared visual identity for the three perspectives, including labels beyond their colors.
extension PinJuror {
    var displayName: LocalizedStringResource {
        switch self {
        case .keeper: .pinJuryKeeperName
        case .scout: .pinJuryScoutName
        case .steward: .pinJuryStewardName
        }
    }

    var perspective: LocalizedStringResource {
        switch self {
        case .keeper: .pinJuryKeeperPerspective
        case .scout: .pinJuryScoutPerspective
        case .steward: .pinJuryStewardPerspective
        }
    }

    var tint: Color {
        switch self {
        case .keeper: .blue
        case .scout: .purple
        case .steward: .orange
        }
    }

    var symbol: String {
        switch self {
        case .keeper: "shield.lefthalf.filled"
        case .scout: "binoculars.fill"
        case .steward: "scale.3d"
        }
    }
}

/// Opaque system surfaces also work with Reduce Transparency enabled.
enum PinJuryStyle {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.09)
}

struct PinJurorAvatar: View {
    let juror: PinJuror
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: juror.symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(juror.tint)
            .frame(width: size, height: size)
            .background(juror.tint.opacity(0.12), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct PinJuryVoteBadge: View {
    let vote: PinJuryVote

    var body: some View {
        Label {
            Text(vote == .keep ? .pinJuryVoteKeep : .pinJuryVoteReplace)
        } icon: {
            Image(systemName: vote == .keep ? "pin.fill" : "arrow.triangle.swap")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.06), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

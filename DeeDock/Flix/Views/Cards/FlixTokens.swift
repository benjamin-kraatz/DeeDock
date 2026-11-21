import SwiftUI

/// "Understood as  [↓ Downloaded ✕] [Last 7 days ✕]". Tokens wrap onto further lines; one that is
/// removed shrinks away and the rest close up (a crossfade with Reduce Motion).
struct FlixTokensBar: View {
    let tokens: [FlixQueryToken]
    var reduceMotion = false
    let remove: (FlixQueryToken.ID) -> Void

    var body: some View {
        FlixFlow(spacing: 5, lineSpacing: 5) {
            Text(.flixUnderstoodAs)
                .frame(height: 22)
            ForEach(tokens) { token in
                FlixTokenChip(label: token.label) { remove(token.id) }
                    .transition(FlixMotion.pop(reduceMotion: reduceMotion))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(FlixStyle.faint)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(FlixMotion.resolved(FlixMotion.arrive, reduceMotion: reduceMotion), value: tokens.map(\.id))
        .accessibilityElement(children: .contain)
    }
}

/// One removable token.
struct FlixTokenChip: View {
    let label: String
    var intelligent = false
    let remove: () -> Void
    @State private var hovered = false

    private var tint: Color { intelligent ? FlixStyle.aiViolet : .accentColor }

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: label)
                .lineLimit(1)
                .truncationMode(.middle)
                // The ✦ is decoration; VoiceOver would spell it out.
                .accessibilityLabel(Text(verbatim: label.replacingOccurrences(of: "✦ ", with: "")))
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(hovered ? tint.opacity(0.22) : .clear, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel(Text(.flixRemoveToken(label)))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(height: 22)
        .frame(maxWidth: 300)
        .foregroundStyle(tint)
        .background(intelligent ? FlixStyle.aiSoft : FlixStyle.accentSoft, in: .capsule)
        .fixedSize()
        .animation(FlixMotion.hover, value: hovered)
    }
}

/// "✦ Like IMG_4821.HEIC ✕  4 by meaning · Lookout".
struct FlixMoreLikeThisBar: View {
    let name: String
    let count: Int?
    let loading: Bool
    var reduceMotion = false
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                FlixTokenChip(label: "✦ " + String(localized: .flixLikeToken(name)), intelligent: true, remove: clear)
                if loading {
                    ProgressView().controlSize(.mini)
                        .transition(.opacity)
                } else if let count {
                    Text(.flixMoreLikeThisCount(count))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(FlixStyle.faint)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 4)
            if loading {
                FlixLoadingRows(reduceMotion: reduceMotion)
                    .transition(.opacity)
            }
        }
        .animation(FlixMotion.resolved(FlixMotion.row, reduceMotion: reduceMotion), value: loading)
    }
}

#if DEBUG
#Preview("Tokens and More like this") {
    VStack(alignment: .leading, spacing: 0) {
        FlixTokensBar(tokens: FlixPreviewData.tokens, remove: { _ in })
        FlixTokensBar(tokens: FlixPreviewData.tokens + [
            FlixQueryToken(label: "über „Verpackungskonzept Oak & Ash Frühjahr“", rule: .nameContains("oak")),
            FlixQueryToken(label: "Letzte 30 Tage", rule: .withinDays(30))], remove: { _ in })
        FlixMoreLikeThisBar(name: "IMG_4821.HEIC", count: 4, loading: false, clear: {})
        FlixMoreLikeThisBar(name: "IMG_4821.HEIC", count: nil, loading: true, clear: {})
    }
    .frame(width: 500)
}
#endif

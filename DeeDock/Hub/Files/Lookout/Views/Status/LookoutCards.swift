import SwiftUI

/// The card Lookout shows in place of results before it's set up (the mockup's `.promo`): the spyglass, "Search by
/// what's inside", one line on what it finds, and "Set up Lookout".
struct LookoutPromoCard: View {
    /// "Search by what's inside", or "Search with a picture" after a picture was dropped.
    var title: LocalizedStringResource = .lookoutPromoTitle
    var message: LocalizedStringResource = .lookoutPromoMessage
    /// Runs "Set up Lookout" (phase 3 connects it to onboarding).
    let onSetUpLookout: () -> Void

    var body: some View {
        LookoutCard {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            LookoutPrimaryButton(title: .lookoutPromoSetUp, action: onSetUpLookout)
        }
    }
}

/// The card while Lookout's model downloads: what's happening, that names work meanwhile, and a progress bar.
struct LookoutDownloadCard: View {
    /// 0…1, or nil when unknown (an indeterminate bar).
    let progress: Double?
    /// What waits for the download: names work meanwhile, or searching with pictures starts after it.
    var message: LocalizedStringResource = .lookoutDownloadMessage

    var body: some View {
        LookoutCard {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                LookoutProgressBar(progress: progress)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: AttributedString {
        var title = AttributedString(localized: .lookoutDownloadTitle)
        if let progress { title += AttributedString(" · " + progress.formatted(.percent.precision(.fractionLength(0)))) }
        return title
    }
}

/// The promo card's frame: a rounded card with a soft Lookout-tinted wash from the leading edge, the spyglass in its
/// tile, then the content in a row.
private struct LookoutCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 14) {
            LookoutGlyph(size: 22)
                .foregroundStyle(lookout.accent)
                .frame(width: 38, height: 38)
                .background(lookout.accentSoft, in: .rect(cornerRadius: 11, style: .continuous))
            content
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background {
            shape.fill(lookout.card)
            shape.fill(LinearGradient(stops: [.init(color: lookout.accentSoft, location: 0),
                                              .init(color: .clear, location: 0.7)],
                                      startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8)))
        }
        .overlay { shape.strokeBorder(lookout.strongLine, lineWidth: 0.5) }
        .padding(8)
    }
}

/// The 4 pt bar in the download card: the Lookout accent over the chip track. Indeterminate (the system's linear
/// spinner, tinted) when the progress isn't known.
private struct LookoutProgressBar: View {
    let progress: Double?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lookout = LookoutTheme(scheme)
        if let progress {
            Capsule()
                .fill(HubFilesTheme(scheme).chipHighlight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(lookout.accent)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 4)
                .animation(HubFilesMotion.animation(.easeOut(duration: 0.3)), value: progress)
                .accessibilityElement()
                .accessibilityValue(Text(verbatim: progress.formatted(.percent.precision(.fractionLength(0)))))
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(lookout.accent)
        }
    }
}

/// The accent "Set up Lookout" button (the mockup's `.cta`).
private struct LookoutPrimaryButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Color.accentColor, in: .rect(cornerRadius: 8))
                .brightness(hovered ? 0.06 : 0)
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.96))
        .onHover { hovered = $0 }
        .fixedSize()
    }
}

#Preview("Promo · dark") {
    LookoutPromoCard {}
        .frame(width: 600)
        .padding()
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
}

#Preview("Promo · light, German") {
    LookoutPromoCard {}
        .frame(width: 600)
        .padding()
        .background(.regularMaterial)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Picture promo and download") {
    VStack {
        LookoutPromoCard(title: .lookoutPicturePromoTitle, message: .lookoutPicturePromoMessage) {}
        LookoutDownloadCard(progress: 0.42, message: .lookoutPictureDownloadMessage)
    }
    .frame(width: 600)
    .padding()
    .background(.regularMaterial)
}

#Preview("Download") {
    VStack {
        LookoutDownloadCard(progress: 0.42)
        LookoutDownloadCard(progress: nil)
    }
    .frame(width: 600)
    .padding()
    .background(.regularMaterial)
}

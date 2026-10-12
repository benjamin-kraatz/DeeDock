import SwiftUI

/// The progress card's second row: pictures, screenshots, PDFs and documents, each with its glyph (onboarding's
/// feed tiles), files read out of all of that kind, and a 3 pt bar. Kinds with no files are left out.
struct LookoutProgressKindsRow: View {
    let kinds: [FileKind: LookoutProgressDisplay.KindProgress]
    var reduceMotion = HubFilesMotion.reduceMotion

    /// The breakdown's order: what people look for most comes first.
    static let order: [FileKind] = [.image, .screenshot, .pdf, .doc]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Self.order, id: \.self) { kind in
                if let progress = kinds[kind], progress.total > 0 {
                    LookoutProgressKindTile(kind: kind, progress: progress, reduceMotion: reduceMotion)
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.lookoutProgressKindsLabel))
    }
}

/// One kind: glyph, name, "1,204 / 2,310", bar.
private struct LookoutProgressKindTile: View {
    let kind: FileKind
    let progress: LookoutProgressDisplay.KindProgress
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let fraction = min(max(Double(progress.done) / Double(max(progress.total, 1)), 0), 1)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: kind.feedSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(lookout.accent)
                    .frame(width: 22, height: 22)
                    .background(lookout.accentSoft, in: .rect(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.progressLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(verbatim: countText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: countText)
            }
            Capsule()
                .fill(HubFilesTheme(scheme).chipHighlight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(fraction >= 1 ? LookoutTheme.ready : lookout.accent)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.lookoutProgressKindValue(
            LookoutProgressFormatting.localized(kind.progressLabel, locale),
            progress.done.formatted(.number.locale(locale)), progress.total.formatted(.number.locale(locale)))))
    }

    private var countText: String {
        "\(progress.done.formatted(.number.locale(locale))) / \(progress.total.formatted(.number.locale(locale)))"
    }
}

extension FileKind {
    /// The breakdown's plural label: "Pictures", "Screenshots", "PDFs", "Documents".
    var progressLabel: LocalizedStringResource {
        switch self {
        case .image: .lookoutProgressKindPictures
        case .screenshot: .lookoutProgressKindScreenshots
        case .pdf: .lookoutProgressKindPDFs
        case .doc: .lookoutProgressKindDocuments
        }
    }
}

#if DEBUG
#Preview("Kinds · German") {
    SettingsCard {
        LookoutProgressKindsRow(kinds: LookoutProgressDisplay.Sample.big.kinds)
    }
    .frame(width: SettingsMetrics.columnWidth)
    .padding(SettingsMetrics.pageInset)
    .environment(\.locale, Locale(identifier: "de"))
}
#endif

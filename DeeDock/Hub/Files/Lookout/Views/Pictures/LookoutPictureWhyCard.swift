import SwiftUI

/// "Why it matched" for a result of a search with a picture (the mockup's `.why` with `.cmp` and `.meter`): what was
/// searched with ≈ the match, side by side, one sentence, and how close it is in three steps.
///
/// A picture shows as its thumbnail; a document or page as a small page with a highlighted line.
struct LookoutPictureWhyCard: View {
    let why: LookoutPictureWhy
    /// What was searched with: its thumbnail when it's a picture.
    let picture: LookoutPictureQuery?
    let queryIsPicture: Bool
    /// The result, for its thumbnail when it's a picture.
    let hit: LookoutHit

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(.lookoutWhyTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                LookoutComparisonSide(caption: .lookoutPictureYours) {
                    if queryIsPicture, let picture {
                        LookoutPictureThumbnail(picture: picture, size: 58)
                    } else {
                        LookoutMiniPage()
                    }
                }
                Text(verbatim: "≈")
                    .font(.system(size: 16))
                    .foregroundStyle(LookoutTheme(scheme).accent)
                    .accessibilityHidden(true)
                LookoutComparisonSide(caption: .lookoutPictureMatch) {
                    if why.resultIsPicture {
                        LookoutThumbnail(item: hit.fileItem, kind: LookoutHitKind(hit))
                    } else {
                        LookoutMiniPage()
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityHidden(true)
            Text(verbatim: why.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            LookoutClosenessMeter(closeness: why.closeness)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(LookoutTheme(scheme).card, in: shape)
        .overlay { shape.strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

/// One side of the comparison: a 58 pt picture over its caption.
private struct LookoutComparisonSide<Content: View>: View {
    let caption: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 4) {
            content.frame(width: 58, height: 58)
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A small page with lines and one highlighted (the mockup's `.pgm`), for a document on either side.
private struct LookoutMiniPage: View {
    private static let lines: [(width: CGFloat, highlighted: Bool)] = [
        (0.6, false), (1, false), (0.8, false), (1, true), (1, false), (0.7, false), (1, false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Self.lines.indices, id: \.self) { index in
                let line = Self.lines[index]
                Capsule()
                    .fill(line.highlighted ? Color(red: 1, green: 204 / 255, blue: 0).opacity(0.6)
                          : Color(red: 199 / 255, green: 199 / 255, blue: 204 / 255))
                    .frame(height: line.highlighted ? 5 : (index == 0 ? 3 : 2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: line.width, anchor: .leading)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .frame(width: 46, height: 58, alignment: .top)
        .background(Color(red: 244 / 255, green: 242 / 255, blue: 238 / 255), in: .rect(cornerRadius: 3))
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5) }
    }
}

/// Three short bars, lit up to the closeness, and its name (the mockup's `.meter`).
struct LookoutClosenessMeter: View {
    let closeness: LookoutPictureWhy.Closeness

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(LookoutPictureWhy.Closeness.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= closeness.rawValue ? LookoutTheme(scheme).accent
                              : HubFilesTheme(scheme).chipHighlight)
                        .frame(width: 14, height: 4)
                }
            }
            Text(verbatim: closeness.title)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.lookoutPictureClosenessLabel(closeness.title)))
    }
}

#Preview("Why it matched · pictures") {
    let beach = LookoutPicturePreviewData.beachResults.groups[0].strong[0]
    let page = LookoutPicturePreviewData.beachResults.groups[1].strong[0]
    VStack(spacing: 10) {
        LookoutPictureWhyCard(why: LookoutPictureWhy(hit: beach, queryIsPicture: true),
                              picture: LookoutPicturePreviewData.dropped, queryIsPicture: true, hit: beach)
        LookoutPictureWhyCard(why: LookoutPictureWhy(hit: page, queryIsPicture: true),
                              picture: LookoutPicturePreviewData.dropped, queryIsPicture: true, hit: page)
        LookoutPictureWhyCard(why: LookoutPictureWhy(hit: page, queryIsPicture: false),
                              picture: LookoutPicturePreviewData.similarLease, queryIsPicture: false, hit: page)
    }
    .frame(width: 240)
    .padding()
    .background(.regularMaterial)
    .environment(\.hubFilesIconSource, .typeOnly)
}

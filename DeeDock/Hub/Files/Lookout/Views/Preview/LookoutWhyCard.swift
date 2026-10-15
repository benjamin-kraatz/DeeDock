import SwiftUI

/// "Why it matched" in the preview column for a selected Lookout hit (the mockup's `.why`): a bold title and one
/// sentence built from what matched, what the hit is and the page ("Page 7 matched by meaning.").
struct LookoutWhyCard: View {
    let why: LookoutWhy

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text(.lookoutWhyTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(verbatim: why.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(LookoutTheme(scheme).card, in: shape)
        .overlay { shape.strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Why it matched") {
    VStack(spacing: 10) {
        LookoutWhyCard(why: LookoutWhy(hit: LookoutPreviewData.lease, isLookup: false))
        LookoutWhyCard(why: LookoutWhy(hit: LookoutPreviewData.beach, isLookup: false))
        LookoutWhyCard(why: LookoutWhy(hit: LookoutPreviewData.sylt, isLookup: false))
        LookoutWhyCard(why: LookoutWhy(hit: LookoutPreviewData.invoice, isLookup: true))
    }
    .frame(width: 240)
    .padding()
    .background(.regularMaterial)
}

import SwiftUI

/// "Page 7" in the corner of the preview well for a Lookout hit that points at a PDF page (the mockup's `.pv .page
/// .pg`), so the person knows which page the match is on before opening the file. Drawn as the result chips are:
/// 10.5 pt in the chip fill with a 6 pt corner, over a hairline so it reads on any Quick Look rendering.
struct LookoutPageBadge: View {
    let page: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(.lookoutPreviewPage(page))
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: shape)
            .background(HubFilesTheme(scheme).chip, in: shape)
            .overlay { shape.strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
            .accessibilityLabel(Text(.lookoutPreviewPage(page)))
    }
}

#Preview("Page badge") {
    HStack(spacing: 12) {
        LookoutPageBadge(page: 7)
        LookoutPageBadge(page: 128)
    }
    .padding(20)
    .background(.regularMaterial)
}

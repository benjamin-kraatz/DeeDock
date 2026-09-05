#if DIRECT_DISTRIBUTION
import SwiftUI

/// Native block layout keeps publisher whitespace out of spacing and aligns wrapped list text.
struct UpdateReleaseNotesView: View {
    let blocks: [UpdateReleaseNoteBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let marker = block.marker {
                        Text(verbatim: marker)
                            .monospacedDigit()
                            .frame(minWidth: 14, alignment: .trailing)
                    }
                    blockText(block)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(block.indentation) * 22)
            }
        }
        .font(.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockText(_ block: UpdateReleaseNoteBlock) -> some View {
        switch block.style {
        case .heading(let level):
            Text(block.text)
                .font(level <= 2 ? .title3.weight(.semibold) : .headline)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(block.text)
        case .code:
            Text(block.text)
                .font(.callout.monospaced())
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
#endif

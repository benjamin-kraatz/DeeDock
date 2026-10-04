import SwiftUI

/// Native block layout keeps publisher whitespace out of spacing and aligns wrapped list text.
struct UpdateReleaseNotesView: View {
    let blocks: [UpdateReleaseNoteBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(blocks) { block in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let marker = block.marker {
                        Text(verbatim: marker)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                    }
                    blockText(block)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(block.indentation) * 22)
                // Headings open a group, so they get air above unless they start the notes.
                .padding(.top, block.isHeading && block.id != blocks.first?.id ? 8 : 0)
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockText(_ block: UpdateReleaseNoteBlock) -> some View {
        switch block.style {
        case .heading(let level):
            Text(block.text)
                .font(level <= 2 ? .headline : .callout.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(block.text)
        case .code:
            Text(block.text)
                .font(.caption.monospaced())
                .padding(10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private extension UpdateReleaseNoteBlock {
    var isHeading: Bool {
        if case .heading = style { true } else { false }
    }
}

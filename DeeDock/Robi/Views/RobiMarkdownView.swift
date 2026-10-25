import SwiftUI

/// A formatted answer laid out as native blocks: paragraphs, headings, lists with hanging indents,
/// quotes, code, rules and tables.
///
/// `text` is the revealed part of `markdown.text`, already styled: fading words, inline styles and
/// links. Each block shows its slice of it, so a block appears with its first revealed word and
/// grows with the pacer. A block's own decoration, such as a list marker or a code block's
/// background, takes the opacity of its first word, so it fades in with it instead of popping in.
struct RobiMarkdownView: View {
    let markdown: RobiMarkdown
    let text: AttributedString

    var body: some View {
        let count = text.characters.count
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleBlocks(count: count).enumerated()), id: \.offset) { index, block in
                RobiMarkdownBlock(block: block, text: text)
                    .padding(.top, index == 0 ? 0 : Self.spacing(before: block, after: markdown.blocks[index - 1]))
            }
        }
    }

    /// Blocks with at least one revealed character. A rule has none of its own and shows once the
    /// text before it is revealed.
    private func visibleBlocks(count: Int) -> ArraySlice<RobiMarkdown.Block> {
        let end = markdown.blocks.firstIndex { block in
            block.range.isEmpty ? block.range.lowerBound > count : block.range.lowerBound >= count
        } ?? markdown.blocks.endIndex
        return markdown.blocks[..<end]
    }

    /// Space above a block: tight between list items, more around headings and between other
    /// blocks, the way a paragraph break reads in a short note.
    static func spacing(before block: RobiMarkdown.Block, after previous: RobiMarkdown.Block) -> CGFloat {
        switch (previous.kind, block.kind) {
        case (_, .heading): 12
        case (.heading, _): 4
        case (.listItem, .listItem): block.followsBlankLine ? 6 : 3
        case (.listItem, _) where block.depth > 0: block.followsBlankLine ? 6 : 3
        default: 8
        }
    }
}

/// One block of a formatted answer, showing its slice of the revealed text.
private struct RobiMarkdownBlock: View {
    let block: RobiMarkdown.Block
    let text: AttributedString

    /// Width of the list marker column, enough for "10."; items' words line up after it.
    static let markerWidth: CGFloat = 18
    static let markerSpacing: CGFloat = 6
    /// One nesting level: a nested item's marker sits under its parent's words.
    static var indent: CGFloat { markerWidth + markerSpacing }

    var body: some View {
        content
            .padding(.leading, CGFloat(block.depth) * Self.indent)
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .paragraph:
            Text(slice(block.range))
        case let .heading(level):
            Text(slice(block.range))
                .font(.system(size: level == 1 ? 15 : level == 2 ? 14 : 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        case let .listItem(marker):
            HStack(alignment: .firstTextBaseline, spacing: Self.markerSpacing) {
                RobiListMarker(marker: marker, depth: block.depth)
                    .frame(minWidth: Self.markerWidth, alignment: .trailing)
                    .opacity(fade(at: block.range.lowerBound))
                Text(slice(block.range))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                    .opacity(fade(at: block.range.lowerBound))
                Text(slice(block.range, colour: .secondary))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code:
            RobiCodeBlock(text: slice(block.range), opacity: fade(at: block.range.lowerBound))
        case .rule:
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 3)
                .accessibilityHidden(true)
        case let .table(columns):
            RobiTable(columns: columns, rows: block.rows.map { row in row.map { slice($0) } },
                      opacity: fade(at: block.range.lowerBound))
        }
    }

    /// The revealed part of `range`, empty when none of it is revealed yet.
    ///
    /// - Parameter colour: Recolours words still fading in, for a block drawn in another colour
    ///   than the answer's. The pacer fades words in the primary colour, so without this they
    ///   would switch colour when their fade ends.
    private func slice(_ range: Range<Int>, colour: Color? = nil) -> AttributedString {
        let count = text.characters.count
        guard range.lowerBound < count else { return AttributedString() }
        let lower = text.characters.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.characters.index(text.startIndex, offsetBy: min(range.upperBound, count))
        var result = AttributedString(text[lower..<upper])
        if let colour {
            // Collected first: writing attributes while iterating the runs view is not allowed.
            let fades = result.runs.compactMap { run in run.robiFade.map { (run.range, $0) } }
            for (range, fade) in fades where result[range].link == nil {
                result[range].foregroundColor = colour.opacity(fade)
            }
        }
        return result
    }

    /// The opacity of the character at `offset` while it fades in, and 1 once it has.
    private func fade(at offset: Int) -> Double {
        guard offset < text.characters.count else { return 0 }
        let index = text.characters.index(text.startIndex, offsetBy: offset)
        return text[index..<text.characters.index(after: index)].runs.first?.robiFade ?? 1
    }
}

/// A list item's bullet or number. Bullets change shape with depth, as in Notes and Pages, so
/// nesting still reads where the indent is small.
private struct RobiListMarker: View {
    let marker: RobiMarkdown.ListMarker
    let depth: Int

    var body: some View {
        switch marker {
        case .bullet:
            Text(verbatim: ["•", "◦", "▪︎"][min(depth, 2)])
                .foregroundStyle(.secondary)
        case let .number(number):
            Text(verbatim: "\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// A fenced code block: monospaced, on a quiet panel, scrolling sideways rather than wrapping so
/// the code keeps its shape.
private struct RobiCodeBlock: View {
    let text: AttributedString
    let opacity: Double

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .strokeBorder(Color.primary.opacity(0.07))
                .opacity(opacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A pipe table: a semibold header over a hairline, columns aligned as the delimiter row asks.
/// Cells wrap within the card's width rather than scrolling.
private struct RobiTable: View {
    let columns: [RobiMarkdown.ColumnAlignment]
    /// Each row's cells, revealed so far. The header row is first.
    let rows: [[AttributedString]]
    let opacity: Double

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        Text(cell)
                            .fontWeight(index == 0 ? .semibold : nil)
                            .multilineTextAlignment(textAlignment(column))
                            .gridColumnAlignment(alignment(column))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if index == 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 1)
                        .gridCellUnsizedAxes(.horizontal)
                        .opacity(opacity)
                }
            }
        }
    }

    /// Rows with at least one revealed cell; the header always shows once the table does.
    private var visibleRows: ArraySlice<[AttributedString]> {
        let end = rows.indices.dropFirst().first { rows[$0].allSatisfy { $0.characters.isEmpty } } ?? rows.endIndex
        return rows[..<end]
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        switch columns.indices.contains(column) ? columns[column] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func textAlignment(_ column: Int) -> TextAlignment {
        switch columns.indices.contains(column) ? columns[column] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

#if DEBUG
/// The answer from the bug report and a denser one with every kind of block, finished, on both
/// card appearances. Streaming is in `RobiAnswerCard`'s previews.
private struct RobiMarkdownPreview: View {
    let source: String
    let dark: Bool

    var body: some View {
        let markdown = RobiMarkdown(RobiReferencedAnswer(source, landmarks: [], isFinished: true), isFinished: true)
        RobiMarkdownView(markdown: markdown, text: RobiAnswerStyling.styled(AttributedString(markdown.text),
                                                                            markdown: markdown))
            .font(.system(size: 13))
            .lineSpacing(2)
            .textSelection(.enabled)
            .padding(14)
            .frame(width: RobiMetrics.cardWidth, alignment: .leading)
            .background(RobiCardBackground(isDark: dark, reduceTransparency: false))
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

#Preview("Markdown, files list, dark") {
    RobiMarkdownPreview(source: RobiPreviewData.markdownAnswer, dark: true)
}
#Preview("Markdown, every block, light") {
    RobiMarkdownPreview(source: RobiPreviewData.markdownShowcase, dark: false)
}
#endif

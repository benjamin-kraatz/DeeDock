import Foundation

/// An answer's Markdown as the card lays it out: the text the person reads with the syntax taken
/// out, the blocks it is set in, and the runs of it that are styled or linked.
///
/// Models format longer answers with headings, lists, emphasis and code. Shown as typed, the
/// asterisks, dashes and backticks read as noise, so the card draws them natively instead. Copy,
/// Replace and Paste still use the Markdown source (`RobiModel.answerText`): a rewrite of Markdown
/// text must keep its syntax, and many apps the answer goes into understand Markdown.
///
/// `text` is what the pacer reveals. Blocks are separated in it by one newline, table cells by a
/// tab, and every range here is a character offset into it, like `RobiReferencedAnswer`'s.
///
/// While the answer streams, syntax that has not fully arrived is held back until it resolves: an
/// unclosed `**` or backtick, a line that may still become a list item, heading, rule or code fence,
/// and a row that may still become a table. So `text` only grows while an answer streams, and the
/// pacer never restarts or shows a marker that later disappears. Once the answer is finished
/// nothing is held back, and unclosed syntax stays as typed.
///
/// Supported: paragraphs, ATX headings, bulleted and numbered lists with nesting, block quotes,
/// fenced code blocks, rules, pipe tables, bold, italic, strikethrough, inline code, web links and
/// backslash escapes. Emphasis does not span lines, and quotes hold only text, not nested blocks.
nonisolated struct RobiMarkdown: Equatable, Sendable {
    enum ListMarker: Equatable, Sendable {
        case bullet
        case number(Int)
    }

    enum ColumnAlignment: Equatable, Sendable {
        case leading, center, trailing
    }

    enum BlockKind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        case listItem(ListMarker)
        case quote
        case code
        case rule
        case table(columns: [ColumnAlignment])
    }

    struct Block: Equatable, Sendable {
        var kind: BlockKind
        /// Character offsets into `text`. Empty for a rule.
        var range: Range<Int>
        /// How deeply the block sits in lists: a nested list item, or a paragraph or code block
        /// that continues an item.
        var depth = 0
        /// The source had a blank line before it, which loosens the spacing between list items.
        var followsBlankLine = false
        /// Tables only: each row's cells as offsets into `text`, the header row first. Every row
        /// has one cell per column.
        var rows: [[Range<Int>]] = []
    }

    enum InlineStyle: Equatable, Sendable {
        case strong, emphasis, strikethrough, code
        case link(URL)
    }

    struct Span: Equatable, Sendable {
        /// Character offsets into `text`.
        var range: Range<Int>
        var style: InlineStyle
    }

    /// The readable text, without the syntax.
    private(set) var text = ""
    private(set) var blocks: [Block] = []
    /// Styled and linked runs. Spans may nest, such as bold inside a link.
    private(set) var spans: [Span] = []
    /// The answer's references to landmarks, moved to offsets into `text`.
    private(set) var references: [RobiReferencedAnswer.Reference] = []

    /// Deepest list nesting the card indents; deeper items are drawn at this depth.
    static let maximumDepth = 3

    /// - Parameters:
    ///   - answer: The answer with its landmark links already taken out. Its text is the Markdown
    ///     source, and its references are offsets into that source.
    ///   - isFinished: The answer is complete or stopped, so nothing more can resolve held syntax.
    init(_ answer: RobiReferencedAnswer, isFinished: Bool) {
        var parser = Parser(source: Array(answer.text), isFinished: isFinished)
        parser.parse()
        text = String(parser.output)
        blocks = parser.blocks
        spans = parser.spans
        references = answer.references.compactMap { reference in
            let mapped = reference.range.compactMap { $0 < parser.displayIndex.count ? parser.displayIndex[$0] : nil }
            guard let first = mapped.min(), let last = mapped.max() else { return nil }
            return .init(range: first..<(last + 1), landmark: reference.landmark)
        }
    }
}

// MARK: - Parsing

nonisolated private extension RobiMarkdown {
    /// One line of the source, without its line break.
    struct Line {
        let start: Int
        let end: Int
        let hasBreak: Bool
    }

    /// The open block a following line may continue.
    enum Container: Equatable {
        case none
        case paragraph
        case listItem
        case quote
        case table(columns: Int)
        case code(fence: Character, length: Int, indent: Int)
    }

    struct Parser {
        let source: [Character]
        let isFinished: Bool
        private(set) var output: [Character] = []
        /// For each source character, its offset in `output`, or nil when it is syntax or held back.
        private(set) var displayIndex: [Int?]
        private(set) var blocks: [Block] = []
        private(set) var spans: [Span] = []

        private var lines: [Line] = []
        private var container = Container.none
        /// Marker columns of the list items that enclose the current line, outermost first.
        private var listColumns: [Int] = []
        private var sawBlankLine = false
        /// Blank lines inside a code block not yet written, so a block never ends in empty lines.
        private var pendingCodeBreaks = 0
        private var codeHasLine = false
        private var blockHasSeparator = false
        private var pendingBreak = false

        init(source: [Character], isFinished: Bool) {
            self.source = source
            self.isFinished = isFinished
            displayIndex = Array(repeating: nil, count: source.count)
            output.reserveCapacity(source.count)
            var start = 0
            for index in source.indices where source[index].isNewline {
                lines.append(Line(start: start, end: index, hasBreak: true))
                start = index + 1
            }
            if start < source.count { lines.append(Line(start: start, end: source.count, hasBreak: false)) }
        }

        /// Reads every line. Stops at the first syntax that has to be held back, since everything
        /// after it is still arriving too.
        mutating func parse() {
            var index = 0
            while index < lines.count {
                guard let consumed = parseLine(at: index) else { break }
                index += consumed
            }
            closeBlock()
        }

        // MARK: Lines

        /// Parses the line at `index`, returning how many lines it used, or nil to hold back the
        /// rest of the answer.
        private mutating func parseLine(at index: Int) -> Int? {
            let line = lines[index]
            let isOpen = !isFinished && index == lines.count - 1 && !line.hasBreak
            let (column, contentStart) = indentation(of: line)
            let end = trimmedEnd(line)

            if case let .code(fence, length, indent) = container {
                return codeLine(line, fence: fence, length: length, indent: indent, isOpen: isOpen) ? 1 : nil
            }
            guard contentStart < end else {
                // A blank line ends the open block. A list continues past it: the next item or
                // indented paragraph finds its depth from `listColumns`.
                container = .none
                sawBlankLine = true
                return 1
            }
            if isOpen, isUndecided(contentStart..<end) { return nil }
            defer { sawBlankLine = false }

            if let fence = codeFence(contentStart..<end) {
                startBlock(.code, depth: nestedDepth(column))
                container = .code(fence: fence.character, length: fence.length, indent: column)
                codeHasLine = false
                pendingCodeBreaks = 0
                return 1
            }
            if let level = headingLevel(contentStart..<end) {
                endLists()
                startBlock(.heading(level: level), depth: 0)
                container = .none
                return inline(skippingSpaces(from: contentStart + level, to: end)..<end, isOpen: isOpen) ? 1 : nil
            }
            if isRule(contentStart..<end) {
                endLists()
                startBlock(.rule, depth: 0)
                container = .none
                return 1
            }
            if let item = listItem(contentStart..<end) {
                startBlock(.listItem(item.marker), depth: listDepth(forMarkerAt: column))
                container = .listItem
                return inline(item.content..<end, isOpen: isOpen) ? 1 : nil
            }
            if source[contentStart] == ">" {
                var start = contentStart
                while start < end, source[start] == ">" { start = skippingSpaces(from: start + 1, to: end) }
                if container == .quote {
                    emitSeparator()
                } else {
                    startBlock(.quote, depth: nestedDepth(column))
                    container = .quote
                }
                return inline(start..<end, isOpen: isOpen) ? 1 : nil
            }
            if source[contentStart] == "|" {
                if case let .table(columns) = container {
                    tableRow(contentStart..<end, columns: columns)
                    return 1
                }
                switch tableStart(at: index) {
                case let .table(alignments):
                    startBlock(.table(columns: alignments), depth: nestedDepth(column))
                    tableRow(contentStart..<end, columns: alignments.count)
                    container = .table(columns: alignments.count)
                    return 2
                case .undecided:
                    return nil
                case .notTable:
                    break
                }
            }
            return paragraphLine(contentStart..<end, column: column, isOpen: isOpen) ? 1 : nil
        }

        /// A line of plain text: it continues the open paragraph, list item or quote, or starts a
        /// paragraph. After a blank line, an indented paragraph belongs to the list item above it.
        private mutating func paragraphLine(_ range: Range<Int>, column: Int, isOpen: Bool) -> Bool {
            switch container {
            case .paragraph, .listItem, .quote:
                emitSeparator()
            default:
                if column < 2 { endLists() }
                startBlock(.paragraph, depth: nestedDepth(column))
                container = .paragraph
            }
            return inline(range, isOpen: isOpen)
        }

        /// A line inside a fenced code block, kept verbatim apart from the fence's indentation.
        /// Returns false to hold back a last line that may still become the closing fence.
        private mutating func codeLine(_ line: Line, fence: Character, length: Int, indent: Int, isOpen: Bool) -> Bool {
            let (_, contentStart) = indentation(of: line)
            let end = trimmedEnd(line)
            // Indentation alone may still become the closing fence, as in a list item's code.
            if isOpen, contentStart >= end { return false }
            let run = run(of: fence, from: contentStart, to: end)
            if run > 0, contentStart + run == end {
                if isOpen { return false }
                if run >= length {
                    container = .none
                    return true
                }
            }
            guard line.start < line.end else {
                if codeHasLine { pendingCodeBreaks += 1 }
                return true
            }
            if codeHasLine { pendingCodeBreaks += 1 }
            for _ in 0..<pendingCodeBreaks { output.append("\n") }
            pendingCodeBreaks = 0
            codeHasLine = true
            // Strip up to the fence's indentation, so code inside a list item starts at its margin.
            var start = line.start
            var stripped = 0
            while start < line.end, stripped < indent, source[start] == " " {
                start += 1
                stripped += 1
            }
            for index in start..<line.end { emit(index) }
            return true
        }

        // MARK: Tables

        private enum TableStart {
            case table([ColumnAlignment])
            case undecided
            case notTable
        }

        /// Whether the row at `index` heads a table: the next line must be a delimiter row such as
        /// `|---|:-:|`. While streaming, a row whose next line has not arrived is undecided.
        private func tableStart(at index: Int) -> TableStart {
            guard index + 1 < lines.count else { return isFinished ? .notTable : .undecided }
            let next = lines[index + 1]
            let (_, start) = indentation(of: next)
            let end = trimmedEnd(next)
            let isDelimiterLike = start < end && source[start..<end].allSatisfy { "|-: \t".contains($0) }
            let nextIsOpen = !isFinished && index + 1 == lines.count - 1 && !next.hasBreak
            // Indentation alone may still become an indented delimiter row.
            if nextIsOpen { return isDelimiterLike || start >= end ? .undecided : .notTable }
            guard isDelimiterLike, source[start..<end].contains("-") else { return .notTable }
            var alignments: [ColumnAlignment] = []
            for cell in cells(start..<end) {
                let text = source[cell].filter { $0 != " " }
                guard !text.isEmpty, text.allSatisfy({ "-:".contains($0) }), text.contains("-") else { return .notTable }
                alignments.append(text.first == ":" && text.last == ":" ? .center : text.last == ":" ? .trailing : .leading)
            }
            return alignments.isEmpty ? .notTable : .table(alignments)
        }

        /// Writes one table row, cells apart by a tab, padded or cut to the table's columns.
        private mutating func tableRow(_ range: Range<Int>, columns: Int) {
            emitSeparatorIfRows()
            var row: [Range<Int>] = []
            let found = cells(range)
            for column in 0..<columns {
                if column > 0 { output.append("\t") }
                let start = spanStart
                if column < found.count { _ = inline(found[column], isOpen: false) }
                row.append(start..<output.count)
            }
            blocks[blocks.count - 1].rows.append(row)
            blocks[blocks.count - 1].range = blocks[blocks.count - 1].range.lowerBound..<output.count
        }

        private mutating func emitSeparatorIfRows() {
            if !blocks[blocks.count - 1].rows.isEmpty { output.append("\n") }
        }

        /// A row's cells: split at pipes that are neither escaped nor inside code, with the outer
        /// pipes and surrounding spaces removed.
        private func cells(_ range: Range<Int>) -> [Range<Int>] {
            var start = range.lowerBound
            var end = range.upperBound
            if start < end, source[start] == "|" { start += 1 }
            if end > start, source[end - 1] == "|", end - 2 < start || source[end - 2] != "\\" { end -= 1 }
            var result: [Range<Int>] = []
            var cellStart = start
            var inCode = false
            var index = start
            while index < end {
                let character = source[index]
                if character == "\\" {
                    index += 2
                    continue
                }
                if character == "`" { inCode.toggle() }
                if character == "|", !inCode {
                    result.append(trimmed(cellStart..<index))
                    cellStart = index + 1
                }
                index += 1
            }
            result.append(trimmed(cellStart..<min(end, source.count)))
            return result
        }

        // MARK: Inline

        /// Writes a run of text with its inline syntax resolved. Returns false when it stopped at
        /// syntax that may still close: only on the last line while streaming (`isOpen`).
        private mutating func inline(_ range: Range<Int>, isOpen: Bool) -> Bool {
            let end = range.upperBound
            var index = range.lowerBound
            while index < end {
                let character = source[index]
                switch character {
                case "\\":
                    if index + 1 < end, source[index + 1].isASCII,
                       source[index + 1].isPunctuation || source[index + 1].isSymbol {
                        emit(index + 1)
                        index += 2
                    } else if index + 1 == end, isOpen {
                        return false
                    } else {
                        emit(index)
                        index += 1
                    }
                case "`":
                    let length = run(of: "`", from: index, to: end)
                    if index + length == end, isOpen { return false }
                    if let close = closingCode(length: length, from: index + length, to: end) {
                        // A closing run that ends the line still arriving may grow into a longer
                        // run, which would close nothing.
                        if isOpen, close + length == end { return false }
                        var start = index + length
                        var stop = close
                        // One space inside each backtick is padding, so `` `x` `` can hold a backtick.
                        if stop - start >= 2, source[start] == " ", source[stop - 1] == " ",
                           !source[start..<stop].allSatisfy({ $0 == " " }) {
                            start += 1
                            stop -= 1
                        }
                        let first = spanStart
                        for position in start..<stop { emit(position) }
                        addSpan(first, .code)
                        index = close + length
                    } else if isOpen {
                        return false
                    } else {
                        for position in index..<(index + length) { emit(position) }
                        index += length
                    }
                case "*", "_", "~":
                    let length = run(of: character, from: index, to: end)
                    // A run at the end of a line still arriving may grow, or be followed by a word.
                    if index + length == end, isOpen { return false }
                    let styles: [InlineStyle]? = switch (character, length) {
                    case ("~", 2): [.strikethrough]
                    case ("~", _): nil
                    case (_, 1): [.emphasis]
                    case (_, 2): [.strong]
                    case (_, 3): [.strong, .emphasis]
                    default: nil
                    }
                    guard let styles, canOpen(character, at: index, length: length, end: end) else {
                        for position in index..<(index + length) { emit(position) }
                        index += length
                        continue
                    }
                    switch closingDelimiter(character, length: length, from: index + length, to: end, isOpen: isOpen) {
                    case let .found(close):
                        let first = spanStart
                        _ = inline((index + length)..<close, isOpen: false)
                        for style in styles { addSpan(first, style) }
                        index = close + length
                    case .undecided:
                        return false
                    case .none where isOpen:
                        return false
                    case .none:
                        for position in index..<(index + length) { emit(position) }
                        index += length
                    }
                case "[":
                    switch webLink(at: index, end: end) {
                    case let .link(label, url, next):
                        let first = spanStart
                        _ = inline(label, isOpen: false)
                        addSpan(first, .link(url))
                        index = next
                    case .incomplete where isOpen:
                        return false
                    case .incomplete, .none:
                        emit(index)
                        index += 1
                    }
                case "<":
                    switch autolink(at: index, end: end) {
                    case let .link(label, url, next):
                        let first = spanStart
                        for position in label { emit(position) }
                        addSpan(first, .link(url))
                        index = next
                    case .incomplete where isOpen:
                        return false
                    case .incomplete, .none:
                        emit(index)
                        index += 1
                    }
                default:
                    emit(index)
                    index += 1
                }
            }
            return true
        }

        /// A delimiter run opens emphasis when a word follows it. An underscore inside a word, as in
        /// `snake_case`, does not.
        private func canOpen(_ character: Character, at index: Int, length: Int, end: Int) -> Bool {
            let next = index + length
            guard next < end, !source[next].isWhitespace else { return false }
            if character == "_", index > 0, source[index - 1].isLetter || source[index - 1].isNumber { return false }
            return true
        }

        private enum Closer {
            case found(Int)
            /// The closer depends on text still arriving: a closing run ends the open line and may
            /// still grow, as `**` does into the `***` that closes bold and italic together, or a
            /// letter after an underscore run may put it inside a word. Or a code span is still
            /// open, and its contents may not close anything.
            case undecided
            case none
        }

        /// Where the delimiters that close emphasis opened before `start` begin, skipping code and
        /// escapes. A run closes when it follows a word and, for underscores, is not inside one.
        ///
        /// Emphasis opened inside is tracked, so its closers are not taken for this one's: in
        /// `*it **bold** it*` the inner `**` pair is passed over. A run as long as an inner opener
        /// and this one together closes both, as the `***` in `**bold *italic***` does, and this
        /// emphasis ends at its last `length` characters.
        private func closingDelimiter(_ character: Character, length: Int, from start: Int, to end: Int,
                                      isOpen: Bool) -> Closer {
            var index = start
            /// Lengths of runs that opened emphasis inside this one and are still unclosed.
            var inner: [Int] = []
            while index < end {
                let current = source[index]
                if current == "\\" {
                    index += 2
                    continue
                }
                if current == "`" {
                    let ticks = run(of: "`", from: index, to: end)
                    if let close = closingCode(length: ticks, from: index + ticks, to: end) {
                        if isOpen, close + ticks == end { return .undecided }
                        index = close + ticks
                        continue
                    }
                    // Unclosed code is literal once the line is complete, but while it arrives its
                    // contents may still turn into code.
                    if isOpen { return .undecided }
                    index += ticks
                    continue
                }
                guard current == character else {
                    index += 1
                    continue
                }
                let found = run(of: character, from: index, to: end)
                let followsWord = index > start && !source[index - 1].isWhitespace
                let insideWord = character == "_" && index + found < end
                    && (source[index + found].isLetter || source[index + found].isNumber)
                if followsWord, !insideWord {
                    if isOpen, index + found == end { return .undecided }
                    if let open = inner.last, found == open {
                        inner.removeLast()
                        index += found
                        continue
                    }
                    if let open = inner.last, found == open + length { return .found(index + open) }
                    if found == length { return .found(index) }
                }
                if canOpen(character, at: index, length: found, end: end) { inner.append(found) }
                index += found
            }
            return .none
        }

        /// The start of the run of exactly `length` backticks that closes a code span.
        private func closingCode(length: Int, from start: Int, to end: Int) -> Int? {
            var index = start
            while index < end {
                guard source[index] == "`" else {
                    index += 1
                    continue
                }
                let found = run(of: "`", from: index, to: end)
                if found == length { return index }
                index += found
            }
            return nil
        }

        private enum LinkMatch {
            case link(label: Range<Int>, url: URL, next: Int)
            case incomplete
            case none
        }

        /// Reads `[label](url)` with a web or mail URL. Landmark links were taken out before
        /// parsing; any other target stays as typed.
        private func webLink(at start: Int, end: Int) -> LinkMatch {
            var index = start + 1
            var depth = 0
            while index < end {
                let character = source[index]
                if character == "\\" {
                    index += 2
                    continue
                }
                if character == "[" { depth += 1 }
                if character == "]" {
                    if depth == 0 { break }
                    depth -= 1
                }
                index += 1
            }
            guard index < end else { return .incomplete }
            let labelEnd = index
            index += 1
            guard index < end else { return .incomplete }
            guard source[index] == "(" else { return .none }
            index += 1
            let urlStart = index
            // Balanced parentheses belong to the URL, as in Wikipedia's `Swift_(programming_language)`.
            var parentheses = 0
            while index < end, !source[index].isWhitespace {
                if source[index] == "(" { parentheses += 1 }
                if source[index] == ")" {
                    if parentheses == 0 { break }
                    parentheses -= 1
                }
                index += 1
            }
            let urlEnd = index
            // An optional title, `[label](url "title")`, is read past and not shown.
            index = skippingSpaces(from: index, to: end)
            if index < end, index > urlEnd, source[index] == "\"" {
                index += 1
                while index < end, source[index] != "\"" { index += 1 }
                guard index < end else { return .incomplete }
                index = skippingSpaces(from: index + 1, to: end)
            }
            guard index < end else { return .incomplete }
            guard source[index] == ")", labelEnd > start + 1,
                  let url = Self.webURL(String(source[urlStart..<urlEnd]))
            else { return .none }
            return .link(label: (start + 1)..<labelEnd, url: url, next: index + 1)
        }

        /// Reads `<https://…>`. While streaming, a `<` that may still become one is incomplete.
        private func autolink(at start: Int, end: Int) -> LinkMatch {
            var index = start + 1
            while index < end, source[index] != ">", !source[index].isWhitespace, source[index] != "<" { index += 1 }
            let candidate = String(source[(start + 1)..<index])
            guard index < end, source[index] == ">" else {
                let scheme = candidate.lowercased()
                let couldGrow = index == end
                    && ["https://", "http://", "mailto:"].contains { $0.hasPrefix(scheme) || scheme.hasPrefix($0) }
                return couldGrow ? .incomplete : .none
            }
            guard let url = Self.webURL(candidate) else { return .none }
            return .link(label: (start + 1)..<index, url: url, next: index + 1)
        }

        /// Only links the browser or Mail can open become links.
        static func webURL(_ string: String) -> URL? {
            guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return nil }
            if scheme != "mailto", url.host() == nil { return nil }
            return url
        }

        // MARK: Block syntax

        /// Whether the last line, still arriving, may yet turn into block syntax, so it must not be
        /// shown as text: a lone `-`, `#`, `1.` or `>`, the start of a fence, a rule, or a table row.
        private func isUndecided(_ range: Range<Int>) -> Bool {
            let text = source[range]
            guard let first = text.first else { return true }
            if text.allSatisfy({ "-*_+•".contains($0) || $0.isWhitespace }) { return true }
            if first == "#" {
                let hashes = text.prefix { $0 == "#" }.count
                return hashes <= 6 && text.dropFirst(hashes).allSatisfy(\.isWhitespace)
            }
            if first.isASCII, first.isNumber {
                let digits = text.prefix { $0.isASCII && $0.isNumber }.count
                let rest = text.dropFirst(digits)
                guard digits <= 9 else { return false }
                if rest.isEmpty { return true }
                return (rest.first == "." || rest.first == ")") && rest.dropFirst().allSatisfy(\.isWhitespace)
            }
            if first == "`" || first == "~" {
                let length = run(of: first, from: range.lowerBound, to: range.upperBound)
                return length == text.count || length >= 3
            }
            if first == ">" { return text.dropFirst().allSatisfy { $0 == ">" || $0.isWhitespace } }
            return first == "|"
        }

        private func codeFence(_ range: Range<Int>) -> (character: Character, length: Int)? {
            let first = source[range.lowerBound]
            guard first == "`" || first == "~" else { return nil }
            let length = run(of: first, from: range.lowerBound, to: range.upperBound)
            guard length >= 3 else { return nil }
            // A backtick fence's info string cannot contain a backtick.
            if first == "`", source[(range.lowerBound + length)..<range.upperBound].contains("`") { return nil }
            return (first, length)
        }

        private func headingLevel(_ range: Range<Int>) -> Int? {
            let level = run(of: "#", from: range.lowerBound, to: range.upperBound)
            guard (1...6).contains(level) else { return nil }
            let next = range.lowerBound + level
            guard next == range.upperBound || source[next] == " " || source[next] == "\t" else { return nil }
            return level
        }

        private func isRule(_ range: Range<Int>) -> Bool {
            let marks = source[range].filter { !$0.isWhitespace }
            guard let first = marks.first, "-*_".contains(first), marks.count >= 3 else { return false }
            return marks.allSatisfy { $0 == first }
        }

        private func listItem(_ range: Range<Int>) -> (marker: ListMarker, content: Int)? {
            let first = source[range.lowerBound]
            var index = range.lowerBound
            let marker: ListMarker
            if "-*+•".contains(first) {
                marker = .bullet
                index += 1
            } else if first.isASCII, first.isNumber {
                while index < range.upperBound, source[index].isASCII, source[index].isNumber,
                      index - range.lowerBound < 9 { index += 1 }
                guard index < range.upperBound, source[index] == "." || source[index] == ")",
                      let number = Int(String(source[range.lowerBound..<index])) else { return nil }
                marker = .number(number)
                index += 1
            } else {
                return nil
            }
            guard index < range.upperBound, source[index] == " " || source[index] == "\t" else { return nil }
            let content = skippingSpaces(from: index, to: range.upperBound)
            return content < range.upperBound ? (marker, content) : nil
        }

        // MARK: Lists

        /// The depth of a list item whose marker is at `column`: deeper than an item whose marker is
        /// further left, level with one in the same column.
        private mutating func listDepth(forMarkerAt column: Int) -> Int {
            while let last = listColumns.last, column < last { listColumns.removeLast() }
            if listColumns.last != column { listColumns.append(column) }
            return min(listColumns.count - 1, RobiMarkdown.maximumDepth)
        }

        /// The depth of a paragraph, code block or quote indented under a list item.
        private func nestedDepth(_ column: Int) -> Int {
            guard column >= 2, let index = listColumns.lastIndex(where: { $0 < column }) else { return 0 }
            return min(index + 1, RobiMarkdown.maximumDepth)
        }

        private mutating func endLists() { listColumns.removeAll() }

        // MARK: Output

        private mutating func startBlock(_ kind: BlockKind, depth: Int) {
            closeBlock()
            pendingBreak = false
            blockHasSeparator = !output.isEmpty
            if blockHasSeparator { output.append("\n") }
            blocks.append(Block(kind: kind, range: output.count..<output.count, depth: depth,
                                followsBlankLine: sawBlankLine))
        }

        /// Settles the last block's range, and drops it when it holds no text, such as a list item
        /// whose words are all held back.
        private mutating func closeBlock() {
            guard let last = blocks.indices.last else { return }
            let lower = blocks[last].range.lowerBound
            pendingBreak = false
            blocks[last].range = lower..<output.count
            guard output.count == lower, blocks[last].kind != .rule else { return }
            if case .table = blocks[last].kind, !blocks[last].rows.isEmpty { return }
            blocks.removeLast()
            if blockHasSeparator { output.removeLast() }
            blockHasSeparator = false
        }

        /// A line break inside a block, written only once the line after it has words to show, so a
        /// line held back whole never leaves an empty line behind.
        private mutating func emitSeparator() {
            pendingBreak = true
        }

        /// Where the next written character will land: after a pending line break.
        private var spanStart: Int { output.count + (pendingBreak ? 1 : 0) }

        private mutating func emit(_ index: Int) {
            if pendingBreak {
                output.append("\n")
                pendingBreak = false
            }
            displayIndex[index] = output.count
            output.append(source[index])
        }

        private mutating func addSpan(_ start: Int, _ style: InlineStyle) {
            guard output.count > start else { return }
            spans.append(Span(range: start..<output.count, style: style))
        }

        // MARK: Helpers

        /// The line's indentation as a column, with tabs to the next multiple of four, and where its
        /// content starts.
        private func indentation(of line: Line) -> (column: Int, contentStart: Int) {
            var column = 0
            var index = line.start
            while index < line.end, source[index] == " " || source[index] == "\t" {
                column += source[index] == "\t" ? 4 - column % 4 : 1
                index += 1
            }
            return (column, index)
        }

        private func trimmedEnd(_ line: Line) -> Int {
            var end = line.end
            while end > line.start, source[end - 1].isWhitespace { end -= 1 }
            return end
        }

        private func trimmed(_ range: Range<Int>) -> Range<Int> {
            var start = range.lowerBound
            var end = range.upperBound
            while start < end, source[start].isWhitespace { start += 1 }
            while end > start, source[end - 1].isWhitespace { end -= 1 }
            return start..<end
        }

        private func skippingSpaces(from start: Int, to end: Int) -> Int {
            var index = start
            while index < end, source[index] == " " || source[index] == "\t" { index += 1 }
            return index
        }

        private func run(of character: Character, from start: Int, to end: Int) -> Int {
            var index = start
            while index < end, source[index] == character { index += 1 }
            return index - start
        }
    }
}

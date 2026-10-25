import Foundation
import Testing
@testable import DeeDock

/// Robi's card draws an answer's Markdown natively. These tests cover what can regress: the text
/// the pacer reveals, the blocks and styles laid over it, and that streaming only ever grows the
/// text, so the pacer never restarts and no syntax flashes on screen.
@Suite("Robi Markdown")
struct RobiMarkdownTests {
    static let filesAnswer = """
    Im Root von **benjamin-kraatz/DeeDock** (Branch `main`) liegen:

    **Ordner**
    - `.agents/skills`, `.githooks`, `.github/workflows`
    - `DeeDock.xcodeproj`, `DeeDock`, `DeeDockTests`

    **Dateien**
    - `.env.example`, `.gitignore`
    """

    static let showcase = """
    ## Fixing the race

    The crash comes from *two* writers. See [the docs](https://developer.apple.com/documentation/swift) or ~~ignore it~~ fix it.

    1. Move the write onto the **main actor**:
       - mark `sync()` as `@MainActor`
       - or hop back with `await MainActor.run`
    2. Remove the second writer.
    10. Ship it.

    > Isolation errors are warnings in Swift 5 mode.

    ```swift
    @MainActor func sync() async {

        items = await store.load()
    }
    ```

    ---

    | Option | Effort | Risk |
    |:--|:-:|--:|
    | Main actor | Low | Low |
    | Actor | Medium | Medium |
    """

    private func parse(_ source: String, landmarks: Set<Int> = [], isFinished: Bool = true) -> RobiMarkdown {
        RobiMarkdown(RobiReferencedAnswer(source, landmarks: landmarks, isFinished: isFinished), isFinished: isFinished)
    }

    private func substring(_ markdown: RobiMarkdown, _ range: Range<Int>) -> String {
        String(Array(markdown.text)[range])
    }

    private func styled(_ markdown: RobiMarkdown, _ style: RobiMarkdown.InlineStyle) -> [String] {
        markdown.spans.filter { $0.style == style }.map { substring(markdown, $0.range) }
    }

    // MARK: Finished answers

    @Test("The answer from the bug report reads without asterisks, dashes or backticks")
    func bugReport() {
        let markdown = parse("""
        Im Root von **benjamin-kraatz/DeeDock** (Branch `main`) liegen:

        **Ordner**
        - `.agents/skills`, `.githooks`
        - `Configuration`
        """)
        #expect(markdown.text == "Im Root von benjamin-kraatz/DeeDock (Branch main) liegen:\nOrdner\n.agents/skills, .githooks\nConfiguration")
        #expect(markdown.blocks.map(\.kind) == [.paragraph, .paragraph, .listItem(.bullet), .listItem(.bullet)])
        #expect(styled(markdown, .strong) == ["benjamin-kraatz/DeeDock", "Ordner"])
        #expect(styled(markdown, .code) == ["main", ".agents/skills", ".githooks", "Configuration"])
    }

    @Test("Headings, numbered and nested lists, quotes, rules and code become blocks")
    func blocks() {
        let markdown = parse("""
        ## Steps
        1. First
           - nested
        2. Second
        > quoted
        ---
        ```swift
        let a = 1
          indented
        ```
        """)
        #expect(markdown.blocks.map(\.kind) == [
            .heading(level: 2), .listItem(.number(1)), .listItem(.bullet), .listItem(.number(2)),
            .quote, .rule, .code,
        ])
        #expect(markdown.blocks.map(\.depth) == [0, 0, 1, 0, 0, 0, 0])
        #expect(substring(markdown, markdown.blocks[6].range) == "let a = 1\n  indented")
    }

    @Test("A pipe table keeps one cell per column and the delimiter row's alignment")
    func table() throws {
        let markdown = parse("""
        | Option | Risk |
        |:--|--:|
        | **Main** actor | Low |
        | Actor |
        """)
        let table = try #require(markdown.blocks.first)
        #expect(table.kind == .table(columns: [.leading, .trailing]))
        #expect(table.rows.map { $0.map { substring(markdown, $0) } } == [["Option", "Risk"], ["Main actor", "Low"], ["Actor", ""]])
        #expect(styled(markdown, .strong) == ["Main"])
    }

    @Test("Prose with stray symbols stays as typed")
    func literalSymbols() {
        let source = "2 * 3 = 6, snake_case_name, a ~ b, items[0], <b> and 5 # 4"
        #expect(parse(source).text == source)
        #expect(parse(source).spans.isEmpty)
    }

    @Test("Inline styles nest and escapes keep their character")
    func inlineStyles() {
        let markdown = parse("***both*** and *it **bold** it* and ~~gone~~ and \\*not\\*")
        #expect(markdown.text == "both and it bold it and gone and *not*")
        #expect(styled(markdown, .strong) == ["both", "bold"])
        #expect(styled(markdown, .emphasis) == ["both", "it bold it"])
        #expect(styled(markdown, .strikethrough) == ["gone"])
    }

    @Test("Web and mail links become links; other targets stay as typed")
    func links() {
        let markdown = parse("See [the docs](https://example.com/a), <mailto:hi@example.com> and [file](/etc/hosts).")
        #expect(markdown.text == "See the docs, mailto:hi@example.com and [file](/etc/hosts).")
        #expect(markdown.spans.map(\.style) == [.link(URL(string: "https://example.com/a")!), .link(URL(string: "mailto:hi@example.com")!)])
    }

    @Test("References move with the text when syntax around them is taken out")
    func references() {
        let markdown = parse("- Press **[Send](#2)** now", landmarks: [2])
        #expect(markdown.text == "Press Send now")
        #expect(markdown.references == [.init(range: 6..<10, landmark: 2)])
    }

    @Test("Emphasis nested at the end of other emphasis closes with it")
    func nestedClosers() {
        let markdown = parse("Use **bold *italic*** and *it **bold***.")
        #expect(markdown.text == "Use bold italic and it bold.")
        #expect(styled(markdown, .strong) == ["bold italic", "bold"])
        #expect(styled(markdown, .emphasis) == ["italic", "it bold"])
    }

    @Test("A combined closer does not swallow a later bold phrase, and code hides asterisks")
    func closerScope() {
        let markdown = parse("Use **bold *italic*** and **more bold**, or **the `**kwargs` parameter**.")
        #expect(markdown.text == "Use bold italic and more bold, or the **kwargs parameter.")
        #expect(styled(markdown, .strong) == ["bold italic", "more bold", "the **kwargs parameter"])
    }

    @Test("A link keeps balanced parentheses in its URL and drops its title")
    func linkParentheses() {
        let markdown = parse("[docs](https://en.wikipedia.org/wiki/Swift_(programming_language) \"Swift\").")
        #expect(markdown.text == "docs.")
        #expect(markdown.spans.map(\.style) == [.link(URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")!)])
    }

    @Test("Tables and code indented under a list item stay in the item")
    func indentedBlocks() {
        let markdown = parse("- Compare:\n\n  | A | B |\n  |---|---|\n  | x | y |\n- Code:\n  ```\n  x\n  ```")
        #expect(markdown.blocks.map(\.kind) == [.listItem(.bullet), .table(columns: [.leading, .leading]), .listItem(.bullet), .code])
        #expect(markdown.blocks.map(\.depth) == [0, 1, 0, 1])
    }

    @Test("Unclosed syntax in a finished answer stays as typed")
    func unclosedWhenFinished() {
        #expect(parse("A **bold start").text == "A **bold start")
        #expect(parse("Run `make").text == "Run `make")
    }

    // MARK: Streaming

    @Test("Syntax that has not fully arrived is held back")
    func holdsPartialSyntax() {
        #expect(parse("A **bol", isFinished: false).text == "A ")
        #expect(parse("Run `ma", isFinished: false).text == "Run ")
        #expect(parse("Intro\n-", isFinished: false).text == "Intro")
        #expect(parse("Intro\n12.", isFinished: false).text == "Intro")
        #expect(parse("Intro\n```swi", isFinished: false).text == "Intro")
        #expect(parse("Intro\n| a | b |\n|--", isFinished: false).text == "Intro")
        #expect(parse("Intro\n| a | b |\n", isFinished: false).text == "Intro")
        #expect(parse("Snake _case_", isFinished: false).text == "Snake ")
    }

    @Test("Revealed text only grows while an answer streams, character by character",
          arguments: [
              RobiMarkdownTests.filesAnswer,
              RobiMarkdownTests.showcase,
              "Plain *x* and **y** with `z`\n\n1. one\n2. two\n\n> q\n> r\nend",
              "Mixed 2*3*4 and a_b_c and ~~s~~ ~x~ \\*e\\* <https://a.b/c>",
              "Use **bold *italic*** and *it **bold*** text\nnext",
              "- Compare:\n\n  | A | B |\n  |---|---|\n  | x | y |\n",
              "- Item\n  ```swift\n  x\n  ```\nDone",
              "Use **the `**kwargs` parameter** here and **bold *italic*** then **more** text.",
              "See [docs](https://en.wikipedia.org/wiki/Swift_(programming_language) \"Swift\") now.",
          ])
    func growsAsPrefix(source: String) {
        let characters = Array(source)
        var previous = ""
        for end in 1...characters.count {
            let text = parse(String(characters[..<end]), isFinished: false).text
            #expect(text.hasPrefix(previous), "\(previous.debugDescription) → \(text.debugDescription)")
            previous = text
        }
        let finished = parse(source).text
        #expect(finished.hasPrefix(previous), "\(previous.debugDescription) → \(finished.debugDescription)")
    }

    @Test("Spans and blocks stay inside the text while streaming")
    func rangesStayInBounds() {
        let characters = Array(Self.showcase)
        for end in 1...characters.count {
            let markdown = parse(String(characters[..<end]), isFinished: false)
            let count = markdown.text.count
            #expect(markdown.spans.allSatisfy { $0.range.upperBound <= count && !$0.range.isEmpty })
            #expect(markdown.blocks.allSatisfy { $0.range.upperBound <= count })
            #expect(markdown.blocks.allSatisfy { !$0.range.isEmpty || $0.kind == .rule })
        }
    }

    @Test("Copy and paste keep the Markdown as written") @MainActor
    func copyKeepsSource() {
        let model = RobiModel()
        model.answer = "Use **bold** and [Send](#2)."
        #expect(model.answerText == "Use **bold** and Send.")
    }
}

import SwiftUI

/// A Lookout row's excerpt, up to two lines, with the query's words highlighted as the mockup's `mark` (a soft
/// yellow behind the text, which keeps its own color). The snippet's « » markers become the highlight and are never
/// drawn.
struct LookoutSnippetText: View {
    let snippet: LookoutSnippet

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(attributed)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        let highlight = LookoutTheme(scheme).mark
        var text = AttributedString()
        for run in snippet.runs {
            var piece = AttributedString(run.text)
            if run.isMatch { piece.backgroundColor = highlight }
            text += piece
        }
        return text
    }
}

#Preview("Snippets") {
    VStack(alignment: .leading, spacing: 10) {
        LookoutSnippetText(snippet: LookoutSnippet(marked: "§ 12 «Tierhaltung»: Die Haltung von Hunden und Katzen bedarf der vorherigen schriftlichen Zustimmung des Vermieters …"))
        LookoutSnippetText(snippet: LookoutSnippet(text: "Customer saw card declined twice before the charge went through", terms: ["declined"]))
    }
    .frame(width: 380)
    .padding(20)
    .background(.regularMaterial)
}

// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// EmbeddingGemma 2's task prompts (model card). Media inputs take no prompt.
///
/// Queries and documents must be framed with these exact strings: vectors made with other framing land elsewhere in
/// the embedding space, and an index built with one framing won't match queries built with another.
nonisolated enum Prompts {
    /// A search query: what the query encoder embeds for a typed search.
    static func query(_ text: String) -> String { "task: search result | query: \(text)" }

    /// A search of code: the model card's prompt for finding code by what it does. Code is embedded as any document is
    /// (`document`, its path in its repository as the title). DigUp measured it against the search prompt on its
    /// real-code eval (2026-10-09, 27 queries): 24 vs 22 in the top 5, MRR 0.79 vs 0.75.
    static func codeQuery(_ text: String) -> String { "task: code retrieval | query: \(text)" }

    /// A document to index. An empty or missing title is written as `none`, as the model card does.
    static func document(title: String?, text: String) -> String {
        "title: \((title?.isEmpty ?? true) ? "none" : title!) | text: \(text)"
    }
}

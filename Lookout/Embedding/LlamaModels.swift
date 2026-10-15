// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// Where the EmbeddingGemma 2 files for llama.cpp are (see `ModelFiles` for which files, and why Q8_0).
///
/// DigUp searched a list of folders (an environment override, Application Support, the Hugging Face cache). Lookout's
/// callers pass the one folder to use instead: the query service chooses between the installed folder and a
/// development override, and the bench takes `--models`.
nonisolated struct LlamaModels: Sendable {
    /// The text part (310 MB): all that queries need.
    let text: URL
    /// The image and audio encoders (555 MB). Nil while only the text part is there.
    let media: URL?

    /// The model files in `folder`. Missing files are a `WorkerError`, so an indexing run stops and its files stay
    /// pending.
    ///
    /// - Throws: `WorkerError.notFound` when `folder` has no text model.
    static func locate(in folder: URL) throws -> LlamaModels {
        let text = folder.appendingPathComponent(ModelFiles.text.name)
        guard FileManager.default.fileExists(atPath: text.path) else {
            throw WorkerError.notFound("no \(ModelFiles.text.name) in \(folder.path); download it from "
                + "\(ModelFiles.text.url.absoluteString)")
        }
        let media = folder.appendingPathComponent(ModelFiles.media.name)
        return LlamaModels(text: text, media: FileManager.default.fileExists(atPath: media.path) ? media : nil)
    }

    /// Both files are in `folder`, so indexing can run (checked without loading anything).
    static func complete(in folder: URL) -> Bool {
        (try? locate(in: folder))?.media != nil
    }
}

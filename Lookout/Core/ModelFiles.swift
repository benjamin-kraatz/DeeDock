// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CryptoKit
import Foundation

/// The EmbeddingGemma 2 files Lookout runs: ggml-org's Q8_0 GGUF conversion at one pinned revision of the repository
/// (made from google/embeddinggemma-2 at 914f7f8, the weights the mlx-vlm reference runs). Never the F16 files: the
/// model's activations overflow float16.
///
/// The app downloads them (phase 1) and the services load them (`LlamaModels`); this is what both agree on. Changing
/// the revision or a file changes the vectors, so every index would have to embed again.
nonisolated enum ModelFiles {
    static let repository = "ggml-org/embeddinggemma-2-GGUF"
    static let revision = "bfcd298762cc34d0357ece5ebdd31791a3a374d8"

    /// One model file, with the size and checksum a download must match.
    struct File: Sendable, Equatable {
        let name: String
        let bytes: Int64
        /// Lowercase hex.
        let sha256: String

        /// Hugging Face's address for this file at the pinned revision (it redirects to a CDN that takes HTTP ranges).
        var url: URL {
            URL(string: "https://huggingface.co/\(ModelFiles.repository)/resolve/\(ModelFiles.revision)/\(name)")!
        }
    }

    /// The text model (310 MB): all that queries need.
    static let text = File(name: "embeddinggemma-2-Q8_0.gguf", bytes: 309_855_456,
                           sha256: "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135")
    /// The image and audio encoders (555 MB).
    static let media = File(name: "mmproj-embeddinggemma-2-Q8_0.gguf", bytes: 554_821_024,
                            sha256: "c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f")
    /// In download order.
    static let all = [text, media]
    static let totalBytes = all.reduce(0) { $0 + $1.bytes }

    /// Where the app keeps them: `~/Library/Application Support/DDock/Lookout/Models`, beside DOKK's other
    /// Application Support data. Debug and release builds share it, so a development build needn't download again.
    static var installed: URL {
        URL.applicationSupportDirectory.appending(path: "DDock/Lookout/Models", directoryHint: .isDirectory)
    }

    /// The files that aren't in `folder` yet. Only verified files get their final name, so being there is enough.
    static func missing(in folder: URL) -> [File] {
        all.filter { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.name).path) }
    }

    /// The SHA-256 of a file as lowercase hex, read in 8 MB pieces (a 555 MB file takes about half a second).
    ///
    /// - Throws: The file can't be opened or read.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let done = try autoreleasepool { () -> Bool in
                guard let data = try handle.read(upToCount: 8 << 20), !data.isEmpty else { return true }
                hasher.update(data: data)
                return false
            }
            if done { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

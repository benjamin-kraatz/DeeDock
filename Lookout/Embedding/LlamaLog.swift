// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CLlama
import Foundation

/// llama.cpp's log is process-wide: warnings and errors go to one file (or stderr), the rest is dropped (it logs a lot
/// at load time).
nonisolated final class LlamaLog: @unchecked Sendable {
    static let shared = LlamaLog()
    nonisolated(unsafe) static let userData = Unmanaged.passUnretained(shared).toOpaque()
    nonisolated(unsafe) static let callback: ggml_log_callback = { level, text, userData in
        guard let text, let userData else { return }
        Unmanaged<LlamaLog>.fromOpaque(userData).takeUnretainedValue().write(level, String(cString: text))
    }

    private let lock = NSLock()
    private var file: FileHandle?             // nil: stderr
    private var level = GGML_LOG_LEVEL_INFO   // CONT continues the previous message, at its level

    func send(to url: URL?) {
        lock.withLock {
            try? file?.close()
            file = nil
            guard let url else { return }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            file = try? FileHandle(forWritingTo: url)
            file?.seekToEndOfFile()
        }
    }

    /// One of our own lines.
    func line(_ message: String) {
        lock.withLock { (file ?? .standardError).write(Data("[llama.cpp worker] \(message)\n".utf8)) }
    }

    private func write(_ level: ggml_log_level, _ text: String) {
        lock.withLock {
            if level != GGML_LOG_LEVEL_CONT { self.level = level }
            guard self.level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue else { return }
            (file ?? .standardError).write(Data(text.utf8))
        }
    }
}

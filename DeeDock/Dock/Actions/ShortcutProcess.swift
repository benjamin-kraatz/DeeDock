import Foundation

/// Owns one invocation of Apple's Shortcuts CLI. Arguments never pass through a shell.
/// Temporary output files avoid pipe backpressure from shortcuts that produce large output.
@MainActor
final class ShortcutProcess {
    private let process = Process()
    private var retained: ShortcutProcess?
    private var cancelled = false
    private var directory: URL?
    private var output: FileHandle?
    private var diagnostics: FileHandle?
    private var completion: ((Result<String, Error>) -> Void)?
    private var timeout: Task<Void, Never>?

    func start(arguments: [String], capturesOutput: Bool = false, deadline: Duration? = nil,
               completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        retained = self
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
            for name in ["output", "error"] {
                guard FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            output = try FileHandle(forWritingTo: directory.appendingPathComponent("output"))
            diagnostics = try FileHandle(forWritingTo: directory.appendingPathComponent("error"))
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = capturesOutput ? output : FileHandle.nullDevice
            process.standardError = diagnostics
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                Task { @MainActor [weak self] in self?.finished(status: status) }
            }
            try process.run()
            if let deadline {
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: deadline) } catch { return }
                    self?.cancel()
                }
            }
        } catch { finish(.failure(error)) }
    }

    /// Stops waiting for the CLI. Previously performed shortcut actions cannot be rolled back.
    func cancel() {
        cancelled = true
        if process.isRunning { process.terminate() }
        else { finish(.failure(CancellationError())) }
    }

    private func read(_ name: String) -> String {
        guard let directory, let file = try? FileHandle(forReadingFrom: directory.appendingPathComponent(name)) else { return "" }
        defer { try? file.close() }
        let data = (try? file.read(upToCount: 1_048_576)) ?? Data()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finished(status: Int32) {
        guard completion != nil else { return }
        if cancelled { finish(.failure(CancellationError())) }
        else if status == 0 { finish(.success(read("output"))) }
        else {
            let message = read("error")
            finish(.failure(NSError(domain: "DeeDock.Shortcuts", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: message.isEmpty ? String(localized: .actionsRunFailed) : message
            ])))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let completion else { return }
        self.completion = nil
        timeout?.cancel(); timeout = nil
        process.terminationHandler = nil
        try? output?.close(); try? diagnostics?.close()
        output = nil; diagnostics = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        completion(result)
        retained = nil
    }
}

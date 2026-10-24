import Foundation

/// Moves items that only Finder can move (owned by root) to the Trash, in one Apple Event.
///
/// Finder asks for the user's password itself (authorization right `com.apple.desktopservices.scripted`);
/// DOKK never sees it. The event goes through `/usr/bin/osascript` because Finder can hold its reply
/// behind an error dialog: in-process `NSAppleScript` would block the main thread until the user
/// answers. macOS attributes the child's Apple Events to DOKK, so DOKK's Automation permission for
/// Finder applies. Paths travel as arguments, never inside script source.
nonisolated enum AppUninstallFinder {
    enum Outcome: Sendable, Equatable {
        case moved
        /// The user cancelled Finder's password prompt (AppleScript error -128).
        case cancelled
        case failed(String)
    }

    private static let script = [
        "on run argv",
        "set theItems to {}",
        "repeat with p in argv",
        "set end of theItems to (POSIX file (p as text) as alias)",
        "end repeat",
        "with timeout of 600 seconds",
        "tell application id \"com.apple.finder\" to delete theItems",
        "end timeout",
        "end run",
    ]

    /// Asks Finder to move `urls` to the Trash.
    ///
    /// Cancelling the calling task stops waiting and terminates `osascript`; Finder may still finish a
    /// move it already started.
    /// - Parameter timeout: How long to wait for Finder, including the password prompt.
    static func moveToTrash(_ urls: [URL], timeout: Duration = .seconds(600)) async -> Outcome {
        guard !urls.isEmpty else { return .moved }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] } + urls.map(\.path)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { finished in
                    let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if finished.terminationStatus == 0 { continuation.resume(returning: .moved) }
                    else if message.contains("(-128)") { continuation.resume(returning: .cancelled) }
                    else { continuation.resume(returning: .failed(message)) }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(returning: .failed(error.localizedDescription))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
                    if process.isRunning { process.terminate() }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private extension Duration {
    nonisolated var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

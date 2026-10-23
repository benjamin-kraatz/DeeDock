import Darwin
import Foundation
@testable import DeeDock

/// A child process of the test runner for the Running in Background tests.
///
/// The child announces itself through marker files rather than timing: it creates `ready` only
/// after its SIGTERM disposition is in place, and `.reportsTerminate` creates `terminated` from
/// its trap, so a test can wait for the moment a SIGTERM pass has reached it. Every child exits
/// on its own within 30 seconds, and cleanup signals it through its kernel-checked identity, so
/// a PID that Foundation has already reaped and the system has reused is never touched.
nonisolated final class BackgroundProcessFixture {
    enum Behavior {
        /// Ends on SIGTERM.
        case plain
        /// Ignores SIGTERM; `exec` keeps that disposition, so only SIGKILL ends it.
        case ignoresTerminate
        /// Ignores SIGTERM but records each one in the `terminated` marker.
        case reportsTerminate
    }

    let identity: BackgroundProcess
    var pid: pid_t { identity.pid }
    private let process: Process
    private let directory: URL

    private init(process: Process, identity: BackgroundProcess, directory: URL) {
        self.process = process
        self.identity = identity
        self.directory = directory
    }

    /// Starts a child and returns once it is ready.
    static func start(_ behavior: Behavior) async throws -> BackgroundProcessFixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: "dokk-bg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ready = directory.appending(path: "ready").path
        let terminated = directory.appending(path: "terminated").path
        let script = switch behavior {
        case .plain:
            "touch '\(ready)'; exec /bin/sleep 30"
        case .ignoresTerminate:
            "trap '' TERM; touch '\(ready)'; exec /bin/sleep 30"
        case .reportsTerminate:
            "trap \"touch '\(terminated)'\" TERM; touch '\(ready)'; i=0; while [ $i -lt 600 ]; do /bin/sleep 0.05; i=$((i+1)); done"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        guard await Self.waitForFile(ready),
              let identity = BackgroundProcess(pid: process.processIdentifier) else {
            process.waitUntilExit()
            throw FixtureError.notReady
        }
        return BackgroundProcessFixture(process: process, identity: identity, directory: directory)
    }

    /// Waits until a SIGTERM has reached a `.reportsTerminate` child. A zero timeout checks once.
    func waitForTerminateSignal(timeout: Duration = .seconds(5)) async -> Bool {
        await Self.waitForFile(directory.appending(path: "terminated").path, timeout: timeout)
    }

    /// Ends the child if it still runs, reaps it, and removes its markers.
    func end() {
        identity.send(SIGKILL)
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: directory)
    }

    private static func waitForFile(_ path: String, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !FileManager.default.fileExists(atPath: path) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    enum FixtureError: Error { case notReady }
}

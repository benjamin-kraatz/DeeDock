import AppKit
import Darwin
import Testing
@testable import DeeDock

/// The stop sequence and its fail-closed rules, driven by a fake Launch Services reader and
/// real child processes of the test runner. No test reads Launch Services or touches an app.
@MainActor
struct BackgroundApplicationMonitorTests {
    private static let url = URL(fileURLWithPath: "/Applications/Fixture.app", isDirectory: true).standardizedFileURL

    @Test("A failed read during Stop turns the feature off for the session and signals nothing")
    func stopReadFailure() async throws {
        let child = try ChildProcess(ignoringTerminate: false)
        defer { child.end() }
        let identity = try #require(BackgroundProcess(pid: child.pid))
        let launchServices = FakeLaunchServices(.success([Self.application(identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read, terminationGrace: .milliseconds(100))
        var reports: [LaunchServicesBackgroundReader.Unavailability] = []
        monitor.didBecomeUnavailable = { reports.append($0) }
        await monitor.refreshAndWait(timeout: .seconds(2))
        #expect(monitor.application(at: Self.url) != nil)

        launchServices.answer(.failure(.unexpectedResult))
        monitor.stopRunningInBackground(at: Self.url)
        #expect(await eventually { monitor.unavailability != nil })
        #expect(monitor.unavailability == .unexpectedResult)
        #expect(monitor.applications.isEmpty)
        #expect(reports == [.unexpectedResult])
        #expect(identity.isStillRunning)

        // Off for the session: a later successful read publishes nothing and reports nothing.
        launchServices.answer(.success([Self.application(identity)]))
        monitor.refresh()
        await monitor.refreshAndWait(timeout: .milliseconds(200))
        #expect(monitor.applications.isEmpty)
        #expect(reports.count == 1)
        monitor.stopRunningInBackground(at: Self.url)
        try await Task.sleep(for: .milliseconds(300))
        #expect(identity.isStillRunning)
        monitor.stop()
    }

    @Test("Without a reopen, a process that ignores SIGTERM is force-quit after the grace period")
    func forceQuitAfterGrace() async throws {
        let child = try ChildProcess(ignoringTerminate: true)
        defer { child.end() }
        let identity = try #require(BackgroundProcess(pid: child.pid))
        let launchServices = FakeLaunchServices(.success([Self.application(identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read, terminationGrace: .milliseconds(200))
        await monitor.refreshAndWait(timeout: .seconds(2))

        monitor.stopRunningInBackground(at: Self.url)
        #expect(await eventually { !identity.isStillRunning })
        monitor.stop()
    }

    @Test("Opening the app during the grace period cancels the force-quit pass, even after a new quit")
    func reopenCancelsForceQuit() async throws {
        let child = try ChildProcess(ignoringTerminate: true)
        defer { child.end() }
        let identity = try #require(BackgroundProcess(pid: child.pid))
        let launchServices = FakeLaunchServices(.success([Self.application(identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read, terminationGrace: .milliseconds(300))
        await monitor.refreshAndWait(timeout: .seconds(2))
        let readsBeforeStop = launchServices.readCount

        monitor.stopRunningInBackground(at: Self.url)
        // The SIGTERM pass reads twice, then the grace period starts.
        #expect(await eventually { launchServices.readCount >= readsBeforeStop + 2 })
        monitor.applicationDidLaunch(at: Self.url)
        // The fake still lists the app, as if the reopened instance had quit again at once.
        try await Task.sleep(for: .milliseconds(700))
        #expect(identity.isStillRunning)
        monitor.stop()
    }

    @Test("A process listed by only one of a pass's two reads is not signalled")
    func attributionMustHoldAcrossReads() async throws {
        let child = try ChildProcess(ignoringTerminate: false)
        defer { child.end() }
        let identity = try #require(BackgroundProcess(pid: child.pid))
        let launchServices = FakeLaunchServices(.success([Self.application(identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read, terminationGrace: .milliseconds(100))
        await monitor.refreshAndWait(timeout: .seconds(2))

        // The second read no longer attributes the PID to the app, as after a PID reuse.
        launchServices.queue([.success([Self.application(identity)]), .success([])])
        monitor.stopRunningInBackground(at: Self.url)
        try await Task.sleep(for: .milliseconds(400))
        #expect(identity.isStillRunning)
        monitor.stop()
    }

    private static func application(_ processes: BackgroundProcess...) -> BackgroundApplication {
        BackgroundApplication(bundleURL: url, bundleIdentifier: "fixture", name: "Fixture", processes: processes)
    }
}

/// The kernel-checked identity that keeps Stop from signalling a reused PID.
struct BackgroundProcessKernelIdentityTests {
    @Test("The kernel refuses a signal sent with another instance's version of the PID")
    func staleVersionIsRefused() throws {
        let child = try ChildProcess(ignoringTerminate: false)
        defer { child.end() }
        let identity = try #require(BackgroundProcess(pid: child.pid))
        var token = try #require(BackgroundProcess.auditToken(for: child.pid))
        // The last word is the process instance's version. Changing it stands for the same PID
        // after reuse; the kernel must not deliver the signal to the live process.
        token.val.7 &+= 1
        let stale = BackgroundProcess(pid: child.pid, token: token)

        #expect(stale != identity)
        #expect(!stale.send(SIGTERM))
        #expect(identity.isStillRunning)
        #expect(identity.send(SIGTERM))
    }
}

/// A child of the test runner. With `ignoringTerminate`, SIGTERM is ignored; `exec` keeps that
/// disposition, so the child is a single `sleep` process that only SIGKILL ends.
private nonisolated final class ChildProcess {
    private let process = Process()
    var pid: pid_t { process.processIdentifier }

    init(ignoringTerminate: Bool) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", (ignoringTerminate ? "trap '' TERM; " : "") + "exec /bin/sleep 30"]
        try process.run()
        // Give the shell time to install the trap before the test signals it.
        usleep(100_000)
    }

    func end() {
        kill(pid, SIGKILL)
        process.waitUntilExit()
    }
}

/// Answers reads from a queue of results, then repeats a standing answer. Reads arrive on the
/// monitor's private queue, so state is guarded by a lock.
private nonisolated final class FakeLaunchServices: @unchecked Sendable {
    typealias Answer = Result<[BackgroundApplication], LaunchServicesBackgroundReader.Unavailability>
    private let lock = NSLock()
    private var standing: Answer
    private var queued: [Answer] = []
    private var reads = 0

    init(_ answer: Answer) { standing = answer }

    var readCount: Int { lock.withLock { reads } }

    func answer(_ answer: Answer) { lock.withLock { standing = answer } }

    func queue(_ answers: [Answer]) { lock.withLock { queued += answers } }

    var read: BackgroundApplicationMonitor.Read {
        { [self] in
            lock.withLock {
                reads += 1
                return queued.isEmpty ? standing : queued.removeFirst()
            }
        }
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
private func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

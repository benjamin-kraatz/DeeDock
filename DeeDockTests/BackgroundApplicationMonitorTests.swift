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
        let child = try await BackgroundProcessFixture.start(.plain)
        defer { child.end() }
        let launchServices = FakeLaunchServices(.success([Self.application(child.identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read)
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
        #expect(child.identity.isStillRunning)

        // Off for the session: a later successful read publishes nothing and reports nothing,
        // and Stop is not attempted again.
        launchServices.answer(.success([Self.application(child.identity)]))
        let reads = launchServices.readCount
        monitor.refresh()
        await monitor.refreshAndWait(timeout: .milliseconds(200))
        monitor.stopRunningInBackground(at: Self.url)
        try await Task.sleep(for: .milliseconds(200))
        #expect(launchServices.readCount == reads)
        #expect(monitor.applications.isEmpty)
        #expect(reports.count == 1)
        #expect(child.identity.isStillRunning)
        monitor.stop()
    }

    @Test("Without a reopen, a process that ignores SIGTERM is force-quit when the grace period ends")
    func forceQuitAfterGrace() async throws {
        let child = try await BackgroundProcessFixture.start(.reportsTerminate)
        defer { child.end() }
        let gate = GraceGate()
        defer { gate.release() }
        let launchServices = FakeLaunchServices(.success([Self.application(child.identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read, gracePeriod: gate.period)
        await monitor.refreshAndWait(timeout: .seconds(2))

        monitor.stopRunningInBackground(at: Self.url)
        #expect(await child.waitForTerminateSignal())
        // Held inside the grace period: no SIGKILL can have been sent yet.
        #expect(await eventually { gate.isWaiting })
        #expect(child.identity.isStillRunning)
        // The child survives SIGTERM by design, so its exit can only come from the SIGKILL pass.
        gate.release()
        #expect(await eventually { !child.identity.isStillRunning })
        monitor.stop()
    }

    @Test("Opening the app during the grace period cancels the force-quit pass, even after a new quit")
    func reopenCancelsForceQuit() async throws {
        let child = try await BackgroundProcessFixture.start(.reportsTerminate)
        defer { child.end() }
        let gate = GraceGate()
        defer { gate.release() }
        let launchServices = FakeLaunchServices(.success([Self.application(child.identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read, gracePeriod: gate.period)
        await monitor.refreshAndWait(timeout: .seconds(2))

        monitor.stopRunningInBackground(at: Self.url)
        #expect(await child.waitForTerminateSignal())
        #expect(await eventually { gate.isWaiting })
        // Reopened while the stop is held inside its grace period.
        monitor.applicationDidLaunch(at: Self.url)
        await monitor.refreshAndWait(timeout: .seconds(2))
        let reads = launchServices.readCount
        // The fake still lists the app, as if the reopened instance had quit again at once.
        // A cancelled stop ends after the grace period without another read or signal; the
        // wait only gives a broken implementation the time to show itself.
        gate.release()
        try await Task.sleep(for: .milliseconds(300))
        #expect(launchServices.readCount == reads)
        #expect(child.identity.isStillRunning)
        monitor.stop()
    }

    @Test("A process listed by only one of a pass's two reads is not signalled")
    func attributionMustHoldAcrossReads() async throws {
        let child = try await BackgroundProcessFixture.start(.reportsTerminate)
        defer { child.end() }
        let launchServices = FakeLaunchServices(.success([Self.application(child.identity)]))
        let monitor = BackgroundApplicationMonitor(read: launchServices.read)
        await monitor.refreshAndWait(timeout: .seconds(2))
        let reads = launchServices.readCount

        // The second read no longer attributes the PID to the app, as after a PID reuse.
        launchServices.queue([.success([Self.application(child.identity)]), .success([])])
        monitor.stopRunningInBackground(at: Self.url)
        // Both reads of the pass and the refresh after it have run once three reads are done.
        #expect(await eventually { launchServices.readCount >= reads + 3 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(!(await child.waitForTerminateSignal(timeout: .zero)))
        #expect(child.identity.isStillRunning)
        monitor.stop()
    }

    private static func application(_ processes: BackgroundProcess...) -> BackgroundApplication {
        BackgroundApplication(bundleURL: url, bundleIdentifier: "fixture", name: "Fixture", processes: processes)
    }
}

/// The kernel-checked identity that keeps Stop from signalling a reused PID.
struct BackgroundProcessKernelIdentityTests {
    @Test("The kernel refuses a signal sent with another instance's version of the PID")
    func staleVersionIsRefused() async throws {
        let child = try await BackgroundProcessFixture.start(.plain)
        defer { child.end() }
        var token = try #require(BackgroundProcess.auditToken(for: child.pid))
        // The last word is the process instance's version. Changing it stands for the same PID
        // after reuse; the kernel must not deliver the signal to the live process.
        token.val.7 &+= 1
        let stale = BackgroundProcess(pid: child.pid, token: token)

        #expect(stale != child.identity)
        #expect(!stale.send(SIGTERM))
        #expect(child.identity.isStillRunning)
        #expect(child.identity.send(SIGTERM))
    }
}

/// Holds a stop inside its grace period until the test releases it.
@MainActor
private final class GraceGate {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    var period: BackgroundApplicationMonitor.GracePeriod {
        { [self] in
            isWaiting = true
            await withCheckedContinuation { continuation = $0 }
        }
    }

    /// Ends the grace period. Safe to call more than once, and before anything waits.
    func release() {
        isWaiting = false
        continuation?.resume()
        continuation = nil
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

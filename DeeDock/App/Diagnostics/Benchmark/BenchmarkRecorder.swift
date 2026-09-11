import AppKit
import QuartzCore

/// Collects signpost intervals, frame pacing, and the app's own resource use during a benchmark run.
/// Exists only when a benchmark launch argument is present.
@MainActor
final class BenchmarkRecorder {
    /// Warm-up iterations run paused so first-use costs (image decoding, lazy views) stay out of the results.
    var paused = false
    private(set) var samples: [PerformanceMetric: [Double]] = [:]
    private var frames: [String: BenchmarkFrameSummary] = [:]
    private var resources: [ProcessResourceSample] = []
    private var resourceTask: Task<Void, Never>?

    func start() {
        PerformanceSignposts.sink = { [weak self] metric, milliseconds in
            guard let self, !paused else { return }
            samples[metric, default: []].append(milliseconds)
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        resourceTask = Task { [weak self] in
            while !Task.isCancelled {
                if let sample = ProcessResourceSample(pid: pid) { self?.resources.append(sample) }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop() {
        PerformanceSignposts.sink = nil
        PerformanceSignposts.tracksInput = false
        resourceTask?.cancel(); resourceTask = nil
    }

    /// Records display-link pacing on `view`'s display while `work` runs.
    func measureFrames(_ scenario: String, on view: NSView?, during work: () async -> Void) async {
        guard let view else { await work(); return }
        let monitor = FrameMonitor()
        let link = view.displayLink(target: monitor, selector: #selector(FrameMonitor.tick(_:)))
        link.add(to: .main, forMode: .common)
        await work()
        link.invalidate()
        if monitor.intervals.count > 1 {
            frames[scenario] = BenchmarkFrameSummary(intervals: monitor.intervals, expected: monitor.expected)
        }
    }

    func report(stage: String) -> BenchmarkStageReport {
        var report = BenchmarkStageReport(stage: stage)
        for (metric, values) in samples {
            report.metrics[metric.rawValue] = BenchmarkDistribution(samples: values)
        }
        report.frames = frames
        if let usage = ProcessResourceSummary(process: "DDock", samples: resources) { report.resources["ddock"] = usage }
        return report
    }
}

/// Display-link target. Intervals are in milliseconds between consecutive callbacks.
private final class FrameMonitor: NSObject {
    private(set) var intervals: [Double] = []
    private(set) var expected = 1_000.0 / 60
    private var last: CFTimeInterval?

    @objc func tick(_ link: CADisplayLink) {
        let frame = (link.targetTimestamp - link.timestamp) * 1_000
        if frame > 0 { expected = frame }
        if let last { intervals.append((link.timestamp - last) * 1_000) }
        last = link.timestamp
    }
}

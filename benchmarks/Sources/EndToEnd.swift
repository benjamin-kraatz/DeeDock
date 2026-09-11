import ApplicationServices
import Foundation

/// Posts real pointer and keyboard events at the dock. DDock, launched with `-DDockBenchmark e2e`, measures
/// from each event's hardware timestamp to the resulting commit and writes the report when told to finish.
///
/// Posting events needs Accessibility access for the terminal running this tool. The tool only checks for
/// it and explains how to grant it; it never changes privacy settings.
enum EndToEnd {
    static func run(geometry url: URL, iterations: Int) {
        guard AXIsProcessTrusted() else {
            fail("""
                Posting input needs Accessibility access for this terminal. Grant it in System Settings >
                Privacy & Security > Accessibility, then run again, or skip this stage with --skip-e2e.
                """, code: 3)
        }
        guard let dock = waitForGeometry(url) else { fail("DDock did not report dock geometry within 30 s.") }
        print("End-to-end: \(iterations) iterations per interaction. Don't touch the mouse or keyboard.")
        let settle = dock.animationDuration + 0.3
        for index in 0..<iterations {
            if dock.autoHide {
                // Leave long enough for the dock to hide completely, then enter the activation zone.
                move(to: dock.restingPoint)
                pause(dock.hideDelay + settle + 0.2)
                move(to: center(dock.activationZone))
                pause(dock.revealDelay + settle)
            } else if !dock.iconCenters.isEmpty {
                move(to: dock.restingPoint)
                pause(0.4)
                move(to: dock.iconCenters[index % dock.iconCenters.count])
                pause(0.3)
            }
            if let launcher = dock.launcher {
                if dock.autoHide {
                    move(to: center(dock.activationZone))
                    pause(dock.revealDelay + settle)
                }
                click(at: center(launcher))
                pause(1.0)
                key(53) // Escape closes the launcher.
                pause(0.6)
            }
        }
        move(to: dock.restingPoint)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("de.benjaminkraatz.DeeDock.benchmark.finish"), object: nil, userInfo: nil,
            deliverImmediately: true)
    }

    private static func waitForGeometry(_ url: URL) -> BenchmarkDockGeometry? {
        for _ in 0..<300 {
            if let data = try? Data(contentsOf: url),
               let geometry = try? JSONDecoder().decode(BenchmarkDockGeometry.self, from: data) { return geometry }
            pause(0.1)
        }
        return nil
    }

    private static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// A jump rather than a glide: the latency starts at the first event inside the target region.
    private static func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private static func click(at point: CGPoint) {
        move(to: point)
        pause(0.15)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            pause(0.05)
        }
    }

    private static func key(_ code: CGKeyCode) {
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    private static func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
}

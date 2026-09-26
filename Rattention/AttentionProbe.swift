import AppKit

/// Opt-in, finite diagnostic sequence for correlating attention requests with an external AX trace.
/// Launch with --attention-probe; normal launches and previews never run this sequence.
@MainActor
enum AttentionProbe {
    private static var started = false

    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--attention-probe"), !started else { return }
        started = true
        let start = Date()
        func record(_ event: String) {
            print(String(format: "%.3f", Date().timeIntervalSince(start)), event,
                  "active=\(NSApp.isActive)")
            fflush(stdout)
        }
        func pause(_ seconds: Double) async throws {
            try await Task.sleep(for: .seconds(seconds))
        }
        var request: Int?
        defer {
            if let request { NSApp.cancelUserAttentionRequest(request) }
        }
        do {
            record("baseline")
            try await pause(5)
            // Hiding our own test window guarantees requests run while inactive.
            NSApp.hide(nil)
            try await pause(2)
            request = NSApp.requestUserAttention(.informationalRequest)
            record("informational id=\(request!)")
            try await pause(8)
            NSApp.cancelUserAttentionRequest(request!)
            record("cancel informational")
            try await pause(3)
            request = NSApp.requestUserAttention(.criticalRequest)
            record("critical id=\(request!)")
            try await pause(12)
            NSApp.cancelUserAttentionRequest(request!)
            record("cancel critical")
            try await pause(5)
            request = NSApp.requestUserAttention(.criticalRequest)
            record("critical activation test id=\(request!)")
            try await pause(7)
            NSApp.unhide(nil)
            NSApp.activate()
            record("activate")
            try await pause(5)
            record("done")
        } catch {
            record("cancelled")
        }
    }
}

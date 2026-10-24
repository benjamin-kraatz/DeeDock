import AppKit
import FoundationModels
import ScreenCaptureKit

func ms(_ t: ContinuousClock.Instant) -> String { let d = ContinuousClock.now - t; return String(format: "%.0fms", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15) }

@main struct FM {
    static func main() async {
        _ = NSApplication.shared
        let local = SystemLanguageModel.default
        print("on-device: availability=\(local.availability) contextSize=\(local.contextSize)")
        print("  vision=\(local.capabilities.contains(.vision)) tools=\(local.capabilities.contains(.toolCalling)) reasoning=\(local.capabilities.contains(.reasoning))")
        let pcc = PrivateCloudComputeLanguageModel()
        print("PCC: availability=\(pcc.availability) quota=\(pcc.quotaUsage.status)")
        print("  vision=\(pcc.capabilities.contains(.vision)) tools=\(pcc.capabilities.contains(.toolCalling)) reasoning=\(pcc.capabilities.contains(.reasoning))")
        if let size = try? await pcc.contextSize { print("  contextSize=\(size)") }

        // Image: capture only our own throwaway target window.
        let wid = CGWindowID(CommandLine.arguments[1])!
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let w = content.windows.first(where: { $0.windowID == wid }) else { print("no target window"); return }
        let cfg = SCStreamConfiguration(); cfg.width = Int(w.frame.width * 2); cfg.height = Int(w.frame.height * 2)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg) else { print("capture failed"); return }

        func run(_ name: String, _ session: LanguageModelSession, image: CGImage?) async {
            let t = ContinuousClock.now
            var first: String?
            do {
                let stream = session.streamResponse {
                    "In one sentence, say what this window shows and quote any text you can read."
                    if let image { Attachment(image) }
                }
                var last = ""
                for try await partial in stream { if first == nil { first = ms(t) }; last = partial.content }
                print("\(name): first token \(first ?? "-"), total \(ms(t))\n  → \(last.prefix(220))")
            } catch { print("\(name): error \(error)") }
        }
        if local.capabilities.contains(.vision) { await run("on-device + image", LanguageModelSession(model: local), image: image) }
        if case .available = pcc.availability { await run("PCC + image", LanguageModelSession(model: pcc), image: pcc.capabilities.contains(.vision) ? image : nil) }
    }
}

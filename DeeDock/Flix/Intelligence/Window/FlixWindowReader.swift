import AppKit
import ApplicationServices
import FoundationModels
import Synchronization

/// The window in front, read for "Fits this window".
nonisolated struct FlixWindowReading: @unchecked Sendable {
    /// The text the chain ended with. May be short when every reader found little.
    var text: String
    /// The window image, kept only when the chain ends at Apple Intelligence.
    var image: CGImage?
    var chain: FlixReaderChain
    /// Words the accessibility read found, for analytics (never the words).
    var accessibilityWords = 0
    /// Words Vision recognized in the capture.
    var recognizedWords = 0

    /// Words in `text`, split on white space.
    static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Which window a reading belongs to. Fits are cached per key until the window changes: another
/// window, another title (a new page, a new conversation), or another app.
nonisolated struct FlixWindowKey: Hashable, Sendable {
    var processIdentifier: pid_t
    var windowID: CGWindowID?
    var title: String?
}

/// Reads one window, in order: its accessibility text (Robi's reader), Vision text recognition on a
/// capture of that window, and the capture itself for Apple Intelligence.
///
/// A later reader runs only when the earlier one found less than ``FlixWindowTextPolicy`` asks for.
/// - Accessibility needs DOKK's Accessibility permission; without it the chain starts at Vision.
///   For Electron and Chromium apps the web tree is switched on (``FlixWebTree``) for this one read
///   and always restored afterwards, even when the read is cancelled.
/// - Vision needs Screen Recording; without it (`CGPreflightScreenCaptureAccess`, which never asks)
///   the step is skipped. Only that one window is captured, and the picture stays in memory.
/// - Apple Intelligence gets the picture only when the system model is available and reports the
///   `.vision` capability.
///
/// Every call to the other app runs off the main actor with a messaging timeout (`RobiWindowText`
/// and `RobiCapture` do their own; the web-tree switch and the window lookups run detached), so a
/// busy app cannot stall the dock.
@MainActor
final class FlixWindowReader {
    private let capture = RobiCapture()

    /// Whether the Apple Intelligence step can run on this Mac.
    nonisolated static var canSeeImages: Bool {
        guard case .available = SystemLanguageModel.default.availability else { return false }
        return SystemLanguageModel.default.capabilities.contains(.vision)
    }

    /// The key for the window `context` names, with its current accessibility title. Cheap: one
    /// attribute read off the main actor.
    func key(for context: FlixFrontmostContext) async -> FlixWindowKey {
        let pid = context.processIdentifier
        let title = await Task.detached(priority: .userInitiated) { () -> String? in
            guard AXIsProcessTrusted() else { return nil }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.1)
            return RobiAX.element(application, kAXFocusedWindowAttribute)
                .flatMap { RobiAX.value($0, kAXTitleAttribute) as? String }
        }.value
        return FlixWindowKey(processIdentifier: pid, windowID: context.windowID, title: title ?? context.windowTitle)
    }

    /// Accessibility text only, without switching on any web tree: what the tile's background count
    /// may use.
    func accessibilityText(for context: FlixFrontmostContext) async -> String {
        guard AXIsProcessTrusted() else { return "" }
        return await RobiWindowText.read(processIdentifier: context.processIdentifier, budget: 0.25, limit: 8_000,
                                         landmarkLimit: 0).text
    }

    /// The full chain. `step` reports each reader as it starts.
    func read(_ context: FlixFrontmostContext, step: @MainActor (FlixReaderChain) -> Void) async -> FlixWindowReading {
        var chain = FlixReaderChain()
        var text = ""
        var axWords = 0
        var ocrWords = 0
        func reading(_ text: String, image: CGImage? = nil) -> FlixWindowReading {
            FlixWindowReading(text: text, image: image, chain: chain, accessibilityWords: axWords, recognizedWords: ocrWords)
        }
        if AXIsProcessTrusted() {
            chain.steps.append(.accessibility)
            step(chain)
            let bundleURL = NSRunningApplication(processIdentifier: context.processIdentifier)?.bundleURL
            let change = await FlixWebTree.enable(processIdentifier: context.processIdentifier, bundleURL: bundleURL)
            text = await RobiWindowText.read(processIdentifier: context.processIdentifier, budget: 0.6, limit: 12_000,
                                             landmarkLimit: 0).text
            // Restored even after cancellation (a detached task ignores it): the flag must never stay on.
            await FlixWebTree.restore(change)
            axWords = FlixWindowReading.wordCount(text)
            if FlixWindowTextPolicy.isEnough(text) {
                chain.succeeded = true
                return reading(text)
            }
        }
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(),
              let windowID = await Task.detached(operation: { Self.windowID(for: context) }).value
        else { return reading(text) }
        chain.steps.append(.vision)
        step(chain)
        guard let image = await capture.image(windowID: windowID), !Task.isCancelled else {
            return reading(text)
        }
        let recognized = await capture.recognizeText(image)
        ocrWords = FlixWindowReading.wordCount(recognized)
        if FlixWindowTextPolicy.isEnough(recognized) {
            chain.succeeded = true
            return reading(recognized)
        }
        if recognized.count > text.count { text = recognized }
        guard Self.canSeeImages, !Task.isCancelled else { return reading(text) }
        chain.steps.append(.appleIntelligence)
        step(chain)
        return reading(text, image: image)
    }

    /// The window server's number for the window `context` names: the one whose bounds match the
    /// app's focused accessibility window, else the frontmost normal window the capture found.
    /// Both use global top-left points, so the frames compare directly. Off the main actor: the
    /// accessibility read can wait on a busy app.
    nonisolated static func windowID(for context: FlixFrontmostContext) -> CGWindowID? {
        let pid = context.processIdentifier
        var frame: CGRect?
        if AXIsProcessTrusted() {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.1)
            frame = RobiAX.element(application, kAXFocusedWindowAttribute).flatMap(RobiAX.frame(of:))
        }
        guard let frame else { return context.windowID }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let match = list.first { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid, (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return abs(rect.minX - frame.minX) < 2 && abs(rect.minY - frame.minY) < 2
                && abs(rect.width - frame.width) < 2 && abs(rect.height - frame.height) < 2
        }
        return (match?[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? context.windowID
    }
}

/// Switches on an Electron or Chromium app's web accessibility tree for one read, off the main
/// actor. The same rules as Robi's `RobiWebAccessibility`: Electron's `AXManualAccessibility` when
/// it is accepted, else Chromium's `AXEnhancedUserInterface`, which must be switched off again.
/// Every call is IPC to that app, so each runs in a detached task with a messaging timeout.
nonisolated enum FlixWebTree {
    /// What was switched on, so it can be switched off again.
    enum Change: Sendable {
        case none
        case enhancedInterface(pid_t)
    }

    static let messagingTimeout: Float = 0.2
    private static let chromiumBundles = Mutex<[URL: Bool]>([:])

    static func enable(processIdentifier pid: pid_t, bundleURL: URL?) async -> Change {
        await Task.detached(priority: .userInitiated) { () -> Change in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            if AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success {
                return .none
            }
            guard isChromium(bundleURL) else { return .none }
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            return .enhancedInterface(pid)
        }.value
    }

    static func restore(_ change: Change) async {
        guard case let .enhancedInterface(pid) = change else { return }
        await Task.detached(priority: .userInitiated) {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }.value
    }

    /// Chromium-based apps ship `chrome_100_percent.pak` inside a framework. Cached per bundle.
    private static func isChromium(_ bundle: URL?) -> Bool {
        guard let bundle else { return false }
        if let known = chromiumBundles.withLock({ $0[bundle] }) { return known }
        let frameworks = bundle.appending(path: "Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        let found = names.contains { name in
            name.hasSuffix(".framework") && FileManager.default.fileExists(
                atPath: frameworks.appending(path: "\(name)/Resources/chrome_100_percent.pak").path)
        }
        chromiumBundles.withLock { $0[bundle] = found }
        return found
    }
}

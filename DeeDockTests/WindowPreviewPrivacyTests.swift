import AppKit
import Testing
@testable import DeeDock

@MainActor
struct WindowPreviewPrivacyTests {
    @Test("Peek shows only cleared frames and requires a fresh reveal after switching windows")
    func revealThroughPeek() async throws {
        let peek = makePeek()
        let state = peek.state
        let safe = try await frame(.clear)
        let sensitive = try await frame(.sensitive)
        let first = state.cards[0], second = state.cards[1]
        #expect(first.thumbnail == nil)
        #expect(state.previewControl(for: first) == nil)
        state.applyPreview(safe, to: first)
        state.applyPreview(sensitive, to: second)
        #expect(state.cards[0].thumbnail != nil)
        #expect(state.cards[1].thumbnail == nil)
        #expect(state.revealedImage(for: state.cards[1]) == nil)

        let reveal = try #require(state.previewControl(for: state.cards[1]))
        reveal.action()
        #expect(state.selectedID == second.id)
        #expect(state.revealedImage(for: state.cards[1]) != nil)
        #expect(state.cards[1].thumbnail == nil) // History, split, and enlarged Peek still see no image.
        let hide = try #require(state.previewControl(for: state.cards[1]))
        #expect(hide.isRevealed)
        hide.action()
        #expect(state.revealedImage(for: state.cards[1]) == nil)
        #expect(state.previewControl(for: state.cards[1])?.isRevealed == false)
        reveal.action()
        state.select(by: 1)
        state.select(by: 1)
        #expect(state.revealedImage(for: state.cards[1]) == nil)
        reveal.action()
        state.hoverPreview(first.id)
        #expect(state.revealedImage(for: state.cards[1]) == nil)
        reveal.action()
        peek.close(returnFocus: false)
        reveal.action()
        #expect(state.cards.isEmpty)
    }

    @Test("Refreshing a clear preview hides it during inference and rejects a stale result or click")
    func refresh() async throws {
        let state = makePeek().state
        let old = state.cards[0]
        let safe = try await frame(.clear)
        let sensitive = try await frame(.sensitive)
        state.applyPreview(safe, to: old)
        #expect(state.cards[0].thumbnail != nil)

        let replacement = WindowPeekCard(window: old.window)
        state.cards[0] = replacement
        #expect(state.cards[0].thumbnail == nil)
        #expect(state.applyPreview(safe, to: old) == nil)
        state.applyPreview(sensitive, to: replacement)
        let reveal = try #require(state.previewControl(for: state.cards[0]))
        reveal.action()
        #expect(state.revealedImage(for: state.cards[0]) != nil)

        let oldHide = try #require(state.previewControl(for: state.cards[0]))
        let next = try await frame(.sensitive)
        state.applyPreview(next, to: replacement)
        reveal.action()
        #expect(state.revealedImage(for: state.cards[0]) == nil)
        let nextReveal = try #require(state.previewControl(for: state.cards[0]))
        nextReveal.action()
        oldHide.action()
        #expect(state.revealedImage(for: state.cards[0]) != nil)
    }

    @Test("Missing and failed inference leave the placeholder and offer no reveal")
    func unavailable() async throws {
        let state = makePeek().state
        let image = try image()
        let badModel = URL(filePath: "/dev/null")
        #expect(!state.cards[0].previewUnavailable)
        state.applyPreview(nil, to: state.cards[0])
        #expect(state.cards[0].previewUnavailable)
        for classifier in [CoreMLWindowPreviewClassifier(modelURL: nil), CoreMLWindowPreviewClassifier(modelURL: badModel)] {
            let failed = await ClassifiedWindowPreview.classify(image, using: classifier)
            #expect(failed.decision == .unavailable)
            state.applyPreview(failed, to: state.cards[0])
            #expect(state.cards[0].thumbnail == nil)
            #expect(state.cards[0].previewUnavailable)
            #expect(state.previewControl(for: state.cards[0]) == nil)
        }
    }

    @Test("A late inference result belongs to its original window and cannot repopulate a closed Peek")
    func delayedResult() async throws {
        let peek = makePeek()
        let state = peek.state
        let request = state.cards[0]
        let image = try image()
        let classifier = SuspendedPreviewClassifier()
        let task = Task { await ClassifiedWindowPreview.classify(image, using: classifier) }
        await classifier.waitForRequest()
        state.select(by: 1)
        #expect(state.cards.allSatisfy { $0.thumbnail == nil })
        await classifier.finish(.sensitive)
        let result = await task.value
        state.applyPreview(result, to: request)
        #expect(state.selectedID == state.cards[1].id)
        #expect(state.cards[1].preview == nil)
        #expect(state.revealedImage(for: state.cards[0]) == nil)
        peek.close(returnFocus: false)

        let reopened = makePeek().state
        #expect(state.applyPreview(result, to: request) == nil)
        #expect(reopened.applyPreview(result, to: request) == nil)
        #expect(reopened.cards.allSatisfy { $0.preview == nil })
    }

    @Test("The bundled Core ML model produces a sensitive confidence score")
    func bundledModel() throws {
        let url = try #require(Bundle.main.url(forResource: "SensitiveWindowPreview", withExtension: "mlmodelc"))
        let model = try WindowPreviewScoring.load(url)
        // The hosted runner lacks Vision's OCR backend. Exercise the same image scoring the app uses.
        let score = try WindowPreviewScoring.score(try image(), model: model)
        #expect((0...1).contains(score))
    }

    private func frame(_ decision: WindowPreviewDecision) async throws -> ClassifiedWindowPreview {
        await ClassifiedWindowPreview.classify(try image(), using: FixedPreviewClassifier(decision: decision))
    }

    private func image() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 240, height: 150, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 150))
        return try #require(context.makeImage())
    }

    private func makePeek() -> WindowPeekPanelController {
        let item = DockItem(reference: ApplicationReference(bundleIdentifier: "test.previewPrivacy",
            url: URL(fileURLWithPath: "/Test/PreviewPrivacy.app"), name: "Test app"),
            icon: NSImage(size: CGSize(width: 32, height: 32)),
            isFavorite: true, isRunning: true, isAvailable: true)
        let anchor = WindowPeekAnchor(icon: CGRect(x: 200, y: 40, width: 48, height: 48), edge: .bottom,
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let peek = WindowPeekPanelController(item: item, anchor: anchor, settings: .defaults, keyboard: true)
        let session = UUID()
        peek.state.cards = (0..<2).map { index in
            let summary = ApplicationWindowSummary(
                token: .init(sessionID: session, id: UUID()), processIdentifier: 42,
                title: "Window \(index)", frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                isMinimized: false, isMain: index == 0)
            return WindowPeekCard(window: summary)
        }
        peek.state.phase = .windows
        peek.state.selectedID = peek.state.cards.first?.id
        return peek
    }
}

private nonisolated struct FixedPreviewClassifier: WindowPreviewClassifying {
    let decision: WindowPreviewDecision

    func classify(_ image: CGImage) async -> WindowPreviewDecision { decision }
}

private actor SuspendedPreviewClassifier: WindowPreviewClassifying {
    private var result: CheckedContinuation<WindowPreviewDecision, Never>?
    private var request: CheckedContinuation<Void, Never>?

    func classify(_ image: CGImage) async -> WindowPreviewDecision {
        await withCheckedContinuation { continuation in
            result = continuation
            request?.resume()
            request = nil
        }
    }

    func waitForRequest() async {
        guard result == nil else { return }
        await withCheckedContinuation { request = $0 }
    }

    func finish(_ decision: WindowPreviewDecision) {
        result?.resume(returning: decision)
        result = nil
    }
}

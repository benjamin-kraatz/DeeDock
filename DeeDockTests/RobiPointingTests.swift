import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

/// Robi's answers point at things in the window: the model links landmarks by number, the card
/// shows the words without the syntax, and the spotlight lands on the landmark's frame. These
/// tests cover what can drift: parsing while streaming, coordinate conversion, and settings.
@Suite("Robi references and landmarks")
struct RobiPointingTests {
    // MARK: Referenced answers

    @Test("A link to a known landmark becomes its words, marked as a reference")
    func parsesLink() {
        let answer = RobiReferencedAnswer("Press [the Send button](#2) to send.", landmarks: [2], isFinished: true)
        #expect(answer.text == "Press the Send button to send.")
        #expect(answer.references == [.init(range: 6..<21, landmark: 2)])
    }

    @Test("A link to a number the context does not have keeps its words and points nowhere")
    func dropsUnknownLandmark() {
        let answer = RobiReferencedAnswer("See [Inbox](#9).", landmarks: [1, 2], isFinished: true)
        #expect(answer.text == "See Inbox.")
        #expect(answer.references.isEmpty)
    }

    @Test("Brackets that are not landmark links stay as they are")
    func keepsOtherBrackets() {
        let text = "Use items[0] or [see docs](https://example.com) and [x](#y)."
        let answer = RobiReferencedAnswer(text, landmarks: [1], isFinished: true)
        #expect(answer.text == text)
        #expect(answer.references.isEmpty)
    }

    @Test("While streaming, a link that has not fully arrived is held back, then appears whole")
    func holdsPartialLink() {
        #expect(RobiReferencedAnswer("Press [the Se", landmarks: [2], isFinished: false).text == "Press ")
        #expect(RobiReferencedAnswer("Press [the Send button](#", landmarks: [2], isFinished: false).text == "Press ")
        let arrived = RobiReferencedAnswer("Press [the Send button](#2", landmarks: [2], isFinished: false)
        #expect(arrived.text == "Press ")
        let closed = RobiReferencedAnswer("Press [the Send button](#2)", landmarks: [2], isFinished: false)
        #expect(closed.text == "Press the Send button")
        #expect(closed.references.count == 1)
    }

    @Test("A finished answer holds nothing back, even an unclosed bracket")
    func flushesWhenFinished() {
        #expect(RobiReferencedAnswer("Press [the Se", landmarks: [2], isFinished: true).text == "Press [the Se")
    }

    @Test("Revealed text only grows while the stream fills in a link, so the pacer never restarts")
    func growsAsPrefix() {
        let full = "Open [Settings](#1), then [General](#3)."
        var previous = ""
        for end in full.indices.map({ full.index(after: $0) }) {
            let text = RobiReferencedAnswer(String(full[..<end]), landmarks: [1, 3], isFinished: false).text
            #expect(text.hasPrefix(previous), "\(previous) → \(text)")
            previous = text
        }
        #expect(previous == "Open Settings, then General.")
    }

    @Test("Copy and paste get the words of every link, whichever landmarks exist") @MainActor
    func plainTextForActions() {
        let model = RobiModel()
        model.answer = "Click [Send](#2) or [Cancel](#8)."
        #expect(model.answerText == "Click Send or Cancel.")
    }

    @Test("Reference links round-trip through their private URL")
    func linkURL() throws {
        let url = try #require(RobiReferenceLink.url(42))
        #expect(RobiReferenceLink.landmark(from: url) == 42)
        #expect(RobiReferenceLink.landmark(from: URL(string: "https://example.com/42")!) == nil)
    }

    // MARK: Landmark geometry

    @Test("AX frames become window-local and are clipped to the window")
    func windowLocalFrames() {
        // A window on a display left of the primary one, so its x is negative.
        let window = CGRect(x: -1200, y: 100, width: 800, height: 600)
        #expect(RobiLandmark.windowLocal(CGRect(x: -1150, y: 140, width: 100, height: 24), window: window)
                == CGRect(x: 50, y: 40, width: 100, height: 24))
        // Half outside the right edge keeps the visible half.
        #expect(RobiLandmark.windowLocal(CGRect(x: -450, y: 140, width: 100, height: 24), window: window)
                == CGRect(x: 750, y: 40, width: 50, height: 24))
        // Content scrolled out of view has no landmark.
        #expect(RobiLandmark.windowLocal(CGRect(x: -1150, y: 900, width: 100, height: 24), window: window) == nil)
    }

    @Test("Vision's lower-left normalized boxes become top-left points in the region")
    func recognizedFrames() {
        let region = CGRect(x: 100, y: 50, width: 400, height: 200)
        let line = RobiRecognizedLine(text: "  Hello  ", box: CGRect(x: 0.25, y: 0.75, width: 0.5, height: 0.25))
        let landmarks = RobiLandmark.recognized([line, RobiRecognizedLine(text: " ", box: line.box)], in: region)
        #expect(landmarks.count == 1)
        #expect(landmarks.first?.label == "Hello")
        // The top quarter of the picture is the top 50 pt of the region.
        #expect(landmarks.first?.frame == CGRect(x: 200, y: 50, width: 200, height: 50))
    }

    @Test("The model reads landmarks as numbered lines with their centres")
    func listsLandmarks() {
        let context = RobiContext(kind: .window, text: "Inbox\nSend", landmarks: [
            RobiLandmark(id: 1, kind: .heading, label: "Inbox", frame: CGRect(x: 10, y: 10, width: 40, height: 20)),
            RobiLandmark(id: 2, kind: .button, label: "Send", frame: CGRect(x: 700, y: 8, width: 60, height: 24)),
        ], windowSize: CGSize(width: 800, height: 600))
        #expect(RobiAgent.contextText(context) == "[#1 heading @ 30,20] Inbox\n[#2 button @ 730,20] Send")
        #expect(RobiAgent.contextText(RobiContext(kind: .selection, text: "Hi")) == "Hi")
    }

    // MARK: Settings

    @Test("Attach Picture is off by default and survives a round trip; older settings load without it")
    func attachPictureSetting() throws {
        #expect(RobiSettings().attachWindowPicture == false)
        var settings = RobiSettings()
        settings.attachWindowPicture = true
        let decoded = try JSONDecoder().decode(RobiSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.attachWindowPicture)
        let older = try JSONDecoder().decode(RobiSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(older.attachWindowPicture == false)
        #expect(older.isEnabled)
    }
}

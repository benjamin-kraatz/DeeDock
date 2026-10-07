import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor struct LineIconMotionTests {
    private func motion(_ json: String) throws -> LineIconMotion {
        try JSONDecoder().decode(LineIconMotion.self, from: Data(json.utf8))
    }

    @Test("A glyph's parts are its subpaths, in the order they were drawn")
    func partsFollowSubpaths() throws {
        let stroke = try #require(LineIconPath.parse("M3 6L21 6M5 6L5 20L19 20Z"))
        let glyph = LineIconGlyph(id: "test", stroke: stroke, fill: nil)
        #expect(glyph.strokeParts.count == 2)
        #expect(glyph.fillParts.isEmpty)
        #expect(glyph.strokeParts[0].boundingBoxOfPath == CGRect(x: 3, y: 6, width: 18, height: 0))
        #expect(glyph.strokeParts[1].boundingBoxOfPath == CGRect(x: 5, y: 6, width: 14, height: 14))
    }

    @Test("A motion starts where its first keyframes say and is at rest once it ends")
    func poseRunsFromFirstFrameToRest() throws {
        let lid = try motion("""
            {"duration": 0.8, "tracks": [
                {"parts": ["s0"], "rotate": [[0, 0], [0.5, 90, "linear"], [1, 0, "linear"]], "anchor": [21, 6]},
                {"parts": ["s1"], "draw": [[0, 0], [0.5, 1, "linear"]]}]}
            """)
        func pose(_ part: LineIconPart, _ progress: Double) -> LineIconPose {
            lid.pose(for: part, at: progress, strokeCount: 2, fillCount: 0)
        }
        #expect(pose(.stroke(0), 1) == .rest)
        #expect(pose(.stroke(1), 1) == .rest)
        #expect(pose(.stroke(1), 0).trimEnd == 0)
        #expect(abs(pose(.stroke(1), 0.25).trimEnd - 0.5) < 1e-9)

        // A quarter turn clockwise about the hinge carries the lid's far end straight up from it.
        let lifted = CGPoint(x: 3, y: 6).applying(pose(.stroke(0), 0.5).transform)
        #expect(abs(lifted.x - 21) < 1e-9)
        #expect(abs(lifted.y - (6 - 18)) < 1e-9)
        // A part no track names stays put.
        #expect(pose(.fill(0), 0.5) == .rest)
    }

    @Test("Tracks compose in order, and a spread staggers the targeted parts")
    func tracksComposeAndStagger() throws {
        let composed = try motion("""
            {"duration": 1, "tracks": [
                {"parts": ["s0"], "scaleY": [[0, 0.5], [0.8, 1, "linear"]], "anchor": [0, 10]},
                {"y": [[0, 4], [0.8, 0, "linear"]]}]}
            """)
        let point = CGPoint(x: 0, y: 20).applying(composed.pose(for: .stroke(0), at: 0, strokeCount: 1, fillCount: 0).transform)
        #expect(point == CGPoint(x: 0, y: 19))

        let staggered = try motion("""
            {"duration": 1, "tracks": [{"parts": "strokes", "draw": [[0, 0], [0.4, 1, "linear"]], "spread": 0.6}]}
            """)
        func drawn(_ index: Int, at progress: Double) -> CGFloat {
            staggered.pose(for: .stroke(index), at: progress, strokeCount: 3, fillCount: 1).trimEnd
        }
        #expect(drawn(0, at: 0.4) == 1)
        #expect(abs(drawn(1, at: 0.5) - 0.5) < 1e-9)
        #expect(drawn(2, at: 0.5) == 0)
        #expect(abs(drawn(2, at: 0.8) - 0.5) < 1e-9)
        // The fill part is outside a strokes-only track.
        #expect(staggered.pose(for: .fill(0), at: 0.2, strokeCount: 3, fillCount: 1) == .rest)
    }

    @Test("Easing curves start and end on their keyframes, and back overshoots between them")
    func easingEndpoints() {
        for easing in [LineIconMotion.Easing.linear, .in, .out, .inOut, .back] {
            #expect(abs(easing.value(at: 0)) < 1e-4)
            #expect(abs(easing.value(at: 1) - 1) < 1e-4)
        }
        #expect(LineIconMotion.Easing.in.value(at: 0.5) < 0.5)
        #expect(LineIconMotion.Easing.out.value(at: 0.5) > 0.5)
        #expect(LineIconMotion.Easing.back.value(at: 0.7) > 1)
    }

    @Test("A motion that would not end at rest, or is malformed, is rejected")
    func decodingRejectsBadMotions() {
        let bad = [
            #"{"duration": 1, "tracks": [{"rotate": [[0, 0], [1, 90]]}]}"#,
            #"{"duration": 1, "tracks": [{"draw": [[0, 0], [0.5, 0.5]]}]}"#,
            #"{"duration": 1, "tracks": [{"scale": [[0.5, 1], [0.2, 0.5], [1, 1]]}]}"#,
            #"{"duration": 1, "tracks": [{"draw": [[0, 0], [0.8, 1]], "spread": 0.5}]}"#,
            #"{"duration": 1, "tracks": [{"parts": ["x0"], "draw": [[0, 0], [1, 1]]}]}"#,
            #"{"duration": 1, "tracks": [{"wobble": [[0, 0], [1, 0]]}]}"#,
            #"{"duration": 0, "tracks": [{"draw": [[0, 0], [1, 1]]}]}"#,
            #"{"duration": 1, "tracks": []}"#,
        ]
        for json in bad {
            #expect(throws: (any Error).self) { try motion(json) }
        }
        // Whole turns draw the same as rest, so a spin may end on one.
        #expect(throws: Never.self) { try motion(#"{"duration": 1, "tracks": [{"rotate": [[0, 0], [1, 720]]}]}"#) }
    }

    @Test("The library prefers a glyph's own motion, falls back by kind, and skips a broken entry")
    func libraryLookup() throws {
        let json = """
            {"motions": {
                "own": {"duration": 0.5, "tracks": [{"draw": [[0, 0], [1, 1]]}]},
                "broken": {"duration": 0.5, "tracks": [{"draw": [[0, 0], [1, 0.5]]}]}},
             "fallbacks": {
                "stroke": [{"duration": 0.6, "tracks": [{"draw": [[0, 0], [1, 1]]}]}],
                "fill": [{"duration": 0.7, "tracks": [{"scale": [[0, 0.5], [1, 1]]}]},
                         {"duration": 0.8, "tracks": [{"scale": [[0, 0.5], [1, 1]]}]}]}}
            """
        let library = LineIconMotionLibrary { Data(json.utf8) }
        let line = try #require(LineIconPath.parse("M2 2L22 22"))
        #expect(library.motion(for: LineIconGlyph(id: "own", stroke: line, fill: nil))?.duration == 0.5)
        #expect(library.motion(for: LineIconGlyph(id: "broken", stroke: line, fill: nil))?.duration == 0.6)
        #expect(library.motion(for: LineIconGlyph(id: "other", stroke: line, fill: line))?.duration == 0.6)

        let mark = LineIconGlyph(id: "some-mark", stroke: nil, fill: line)
        let picked = try #require(library.motion(for: mark)?.duration)
        #expect([0.7, 0.8].contains(picked))
        #expect(library.motion(for: mark)?.duration == picked)
        // The pick must survive a relaunch, which Hasher's per-process seed would not.
        #expect(LineIconMotionLibrary.stableHash("a") == 0xE40C_292C)

        let empty = LineIconMotionLibrary { nil }
        #expect(empty.motion(for: mark) == nil)
    }

    @Test("Every motion in the bundled library decodes and names parts its glyph has")
    func bundledLibraryIsValid() throws {
        let bundle = Bundle.main
        let motionsURL = try #require(bundle.url(forResource: "LineIconMotions", withExtension: "json"))
        let catalogURL = try #require(bundle.url(forResource: "LineIcons", withExtension: "json"))
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: motionsURL)) as? [String: Any])
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let glyphs = try #require(catalog["glyphs"] as? [String: [String: [String]]])
        let motions = try #require(document["motions"] as? [String: Any])
        #expect(!motions.isEmpty)

        for (reference, value) in motions {
            let decoded = try? JSONDecoder().decode(LineIconMotion.self, from: JSONSerialization.data(withJSONObject: value))
            let motion = try #require(decoded, "\(reference) does not decode")
            let paths = try #require(glyphs[reference], "\(reference) is not in the catalog")
            let counts = ["stroke", "fill"].map { layer in
                (paths[layer] ?? []).reduce(0) { $0 + $1.split(separator: "M", omittingEmptySubsequences: true).count }
            }
            for track in motion.tracks {
                guard case .parts(let parts) = track.target else { continue }
                for part in parts {
                    switch part {
                    case .stroke(let index): #expect(index < counts[0], "\(reference) has no stroke part \(index)")
                    case .fill(let index):
                        #expect(index < counts[1], "\(reference) has no fill part \(index)")
                        #expect(track.property != .draw && track.property != .erase, "\(reference) trims a fill part")
                    }
                }
            }
        }
        let fallbacks = try #require(document["fallbacks"] as? [String: [Any]])
        for value in (fallbacks["stroke"] ?? []) + (fallbacks["fill"] ?? []) {
            #expect((try? JSONDecoder().decode(LineIconMotion.self, from: JSONSerialization.data(withJSONObject: value))) != nil)
        }
    }
}

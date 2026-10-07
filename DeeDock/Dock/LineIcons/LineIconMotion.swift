import CoreGraphics
import Foundation

/// One piece of a glyph that a ``LineIconMotion`` can move on its own: a single subpath of the
/// stroke or fill layer, numbered in catalog order.
nonisolated enum LineIconPart: Hashable, Sendable {
    case stroke(Int), fill(Int)

    /// Reads the `LineIconMotions.json` spelling: `s0` is the first stroke part, `f2` the third fill part.
    init?(token: String) {
        guard let kind = token.first, let index = Int(token.dropFirst()), index >= 0 else { return nil }
        switch kind {
        case "s": self = .stroke(index)
        case "f": self = .fill(index)
        default: return nil
        }
    }
}

/// How one part is drawn at one instant of a ``LineIconMotion``.
nonisolated struct LineIconPose: Equatable, Sendable {
    /// Moves the part inside the 24-point catalog box. It applies after trimming, so a squashed
    /// stroke keeps its line width.
    var transform = CGAffineTransform.identity
    /// The drawn span of a stroke part, as fractions of its length. Fill parts ignore it.
    var trimStart: CGFloat = 0
    var trimEnd: CGFloat = 1

    /// The part exactly as the catalog draws it.
    static let rest = LineIconPose()
}

/// A short choreography a glyph plays once, such as a bell that swings or a lid that lifts.
///
/// A motion is a list of tracks. Each track animates one property of some parts through keyframes
/// placed on a 0...1 timeline, which ``duration`` stretches to seconds. Tracks apply in order, so a
/// part-level track (eyes that blink) composes with a later whole-glyph track (a head that tilts).
///
/// Every track ends on its resting value. Decoding rejects a motion that does not, which is what
/// lets the artwork switch back to the plain resting glyph at the end of a play without a jump.
/// The first frame may differ from rest: a draw-on starts from nothing.
nonisolated struct LineIconMotion: Equatable, Sendable {
    /// Seconds one play takes.
    let duration: TimeInterval
    let tracks: [Track]

    /// The shape of the change between two keyframes, as CSS-style cubic Bézier timing curves.
    nonisolated enum Easing: String, Sendable {
        case linear
        case `in`
        case out
        case inOut
        /// Runs past the keyframe's value by about a tenth of the change, then settles on it.
        case back

        private var controls: (x1: Double, y1: Double, x2: Double, y2: Double) {
            switch self {
            case .linear: (0, 0, 1, 1)
            case .in: (0.42, 0, 1, 1)
            case .out: (0, 0, 0.58, 1)
            case .inOut: (0.42, 0, 0.58, 1)
            case .back: (0.34, 1.56, 0.64, 1)
            }
        }

        /// The eased share of the change at `fraction` of the way between two keyframes.
        func value(at fraction: Double) -> Double {
            let x = min(max(fraction, 0), 1)
            guard self != .linear else { return x }
            let (x1, y1, x2, y2) = controls
            func curve(_ t: Double, _ a: Double, _ b: Double) -> Double {
                let u = 1 - t
                return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
            }
            // The curve's x is monotonic in t, so bisection always converges; 24 steps is past
            // the precision a 120 Hz frame can show.
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if curve(middle, x1, x2) < x { low = middle } else { high = middle }
            }
            return curve((low + high) / 2, y1, y2)
        }
    }

    nonisolated struct Keyframe: Equatable, Sendable {
        /// Position on the motion's 0...1 timeline.
        let time: Double
        let value: Double
        /// Shapes the change that arrives at this keyframe.
        let easing: Easing
    }

    /// What a track animates. Distances are catalog units; angles are degrees, clockwise on screen.
    nonisolated enum Property: String, Sendable, CaseIterable {
        case rotate
        case x
        case y
        case scale
        case scaleX
        case scaleY
        /// A turn about the vertical axis through the anchor, drawn flat: 360 is one full coin flip.
        case turn
        /// How much of a stroke part is drawn, from its start: 0 hides it and 1 is the whole stroke.
        case draw
        /// How much of a stroke part is removed, from its start.
        case erase

        /// The value that leaves a part untouched.
        var rest: Double {
            switch self {
            case .rotate, .x, .y, .turn, .erase: 0
            case .scale, .scaleX, .scaleY, .draw: 1
            }
        }

        /// Whether `value` draws the same as ``rest``; whole turns do.
        func isRest(_ value: Double) -> Bool {
            switch self {
            case .rotate, .turn: abs((value / 360).rounded() * 360 - value) < 1e-6
            default: abs(value - rest) < 1e-6
            }
        }

        fileprivate func apply(_ value: Double, anchor: CGPoint, to pose: inout LineIconPose) {
            func about(_ change: CGAffineTransform) -> CGAffineTransform {
                CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                    .concatenating(change)
                    .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
            }
            let change: CGAffineTransform
            switch self {
            case .rotate: change = about(CGAffineTransform(rotationAngle: value * .pi / 180))
            case .x: change = CGAffineTransform(translationX: value, y: 0)
            case .y: change = CGAffineTransform(translationX: 0, y: value)
            case .scale: change = about(CGAffineTransform(scaleX: value, y: value))
            case .scaleX: change = about(CGAffineTransform(scaleX: value, y: 1))
            case .scaleY: change = about(CGAffineTransform(scaleX: 1, y: value))
            case .turn: change = about(CGAffineTransform(scaleX: cos(value * .pi / 180), y: 1))
            case .draw:
                pose.trimEnd = min(max(value, 0), 1)
                return
            case .erase:
                pose.trimStart = min(max(value, 0), 1)
                return
            }
            pose.transform = pose.transform.concatenating(change)
        }
    }

    /// The parts a track moves.
    nonisolated enum Target: Equatable, Sendable {
        case all
        case strokes
        case fills
        case parts([LineIconPart])

        /// Where `part` sits among the targeted parts, or nil when the track does not move it.
        fileprivate func slot(of part: LineIconPart, strokeCount: Int, fillCount: Int) -> (index: Int, count: Int)? {
            switch (self, part) {
            case (.all, .stroke(let index)): (index, strokeCount + fillCount)
            case (.all, .fill(let index)): (strokeCount + index, strokeCount + fillCount)
            case (.strokes, .stroke(let index)): (index, strokeCount)
            case (.fills, .fill(let index)): (index, fillCount)
            case (.parts(let list), _): list.firstIndex(of: part).map { ($0, list.count) }
            default: nil
            }
        }
    }

    nonisolated struct Track: Equatable, Sendable {
        let target: Target
        let property: Property
        /// The fixed point of a rotation, scale, or turn, in catalog units.
        let anchor: CGPoint
        /// Staggers the targeted parts: the last one starts this far along the timeline after the
        /// first, and the parts between are spaced evenly.
        let spread: Double
        /// At least one, in ascending time order.
        let keyframes: [Keyframe]

        /// The property's value at `time`; it holds the first keyframe before it and the last after.
        func value(at time: Double) -> Double {
            guard let first = keyframes.first, let last = keyframes.last else { return property.rest }
            if time <= first.time { return first.value }
            if time >= last.time { return last.value }
            guard let next = keyframes.firstIndex(where: { $0.time > time }), next > 0 else { return last.value }
            let from = keyframes[next - 1], to = keyframes[next]
            let fraction = (time - from.time) / (to.time - from.time)
            return from.value + (to.value - from.value) * to.easing.value(at: fraction)
        }
    }

    /// The pose of one part at `progress` through the motion, 0 at the start and 1 at rest.
    ///
    /// - Parameters:
    ///   - strokeCount: How many stroke parts the glyph has; a staggered track needs it to place this part.
    ///   - fillCount: How many fill parts the glyph has.
    func pose(for part: LineIconPart, at progress: Double, strokeCount: Int, fillCount: Int) -> LineIconPose {
        var pose = LineIconPose.rest
        guard progress < 1 else { return pose }
        for track in tracks {
            guard let slot = track.target.slot(of: part, strokeCount: strokeCount, fillCount: fillCount) else { continue }
            let delay = slot.count > 1 ? track.spread * Double(slot.index) / Double(slot.count - 1) : 0
            track.property.apply(track.value(at: progress - delay), anchor: track.anchor, to: &pose)
        }
        return pose
    }
}

// MARK: - Decoding `LineIconMotions.json`

extension LineIconMotion: Decodable {
    private nonisolated enum CodingKeys: String, CodingKey {
        case duration, tracks
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(Double.self, forKey: .duration)
        tracks = try container.decode([Track].self, forKey: .tracks)
        guard duration > 0, duration <= 3, !tracks.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .duration, in: container,
                                                   debugDescription: "A motion needs tracks and a duration of at most 3 seconds")
        }
    }
}

extension LineIconMotion.Keyframe: Decodable {
    /// Reads `[time, value]` or `[time, value, "easing"]`; easing defaults to `inOut`.
    nonisolated init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        time = try container.decode(Double.self)
        value = try container.decode(Double.self)
        easing = container.isAtEnd ? .inOut : try container.decode(LineIconMotion.Easing.self)
    }
}

extension LineIconMotion.Easing: Decodable {}

extension LineIconMotion.Track: Decodable {
    private nonisolated struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Reads a track such as `{"parts": ["s1"], "rotate": [[0, 0], [0.3, 20, "out"], [0.8, 0]], "anchor": [21, 6]}`.
    ///
    /// The property name is the key that holds the keyframes. `parts` is `"all"` (the default),
    /// `"strokes"`, `"fills"`, or a list of part tokens. `anchor` defaults to the center of the box.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        func invalid(_ message: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: message))
        }
        guard let property = LineIconMotion.Property.allCases.first(where: { container.contains(Key($0.rawValue)) }) else {
            throw invalid("A track needs one property")
        }
        self.property = property
        keyframes = try container.decode([LineIconMotion.Keyframe].self, forKey: Key(property.rawValue))
        spread = try container.decodeIfPresent(Double.self, forKey: Key("spread")) ?? 0
        if let anchor = try container.decodeIfPresent([Double].self, forKey: Key("anchor")) {
            guard anchor.count == 2 else { throw invalid("An anchor is [x, y]") }
            self.anchor = CGPoint(x: anchor[0], y: anchor[1])
        } else {
            anchor = CGPoint(x: LineIconPath.canvas / 2, y: LineIconPath.canvas / 2)
        }
        if let tokens = try? container.decode([String].self, forKey: Key("parts")) {
            let parts = tokens.compactMap(LineIconPart.init(token:))
            guard !parts.isEmpty, parts.count == tokens.count else { throw invalid("Part tokens look like s0 or f2") }
            target = .parts(parts)
        } else {
            switch try container.decodeIfPresent(String.self, forKey: Key("parts")) {
            case nil, "all": target = .all
            case "strokes": target = .strokes
            case "fills": target = .fills
            default: throw invalid("parts is all, strokes, fills, or a list of part tokens")
            }
        }
        guard let first = keyframes.first, let last = keyframes.last,
              first.time >= 0, spread >= 0, last.time + spread <= 1 + 1e-9,
              zip(keyframes, keyframes.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            throw invalid("Keyframe times ascend within 0...1, with room left for the spread")
        }
        guard property.isRest(last.value) else { throw invalid("A track ends on its resting value") }
    }
}

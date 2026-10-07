import CoreGraphics
import Foundation

/// Parses the path data that `scripts/line-icons/build-line-icons.py` writes.
///
/// The build step normalizes every source SVG to absolute `M`, `L`, `C`, and `Z` commands in a
/// 24-point box, so this parser does not handle relative commands, arcs, or quadratics. Anything else
/// makes the whole path invalid rather than drawing part of a glyph.
nonisolated enum LineIconPath {
    /// The side of the square every catalog glyph is drawn in.
    static let canvas: CGFloat = 24

    /// Returns nil for malformed data, including unsupported commands and missing coordinates.
    static func parse(_ data: String) -> CGPath? {
        let path = CGMutablePath()
        var scanner = Tokens(data)
        var command: Character?
        var drewSomething = false
        while let token = scanner.next() {
            switch token {
            case .command(let value):
                command = value
                if value == "Z" {
                    guard !path.isEmpty else { return nil }
                    path.closeSubpath()
                    continue
                }
                guard let point = scanner.point() else { return nil }
                switch value {
                case "M": path.move(to: point)
                case "L":
                    guard !path.isEmpty else { return nil }
                    path.addLine(to: point)
                    drewSomething = true
                case "C":
                    guard !path.isEmpty, let control2 = scanner.point(), let end = scanner.point() else { return nil }
                    path.addCurve(to: end, control1: point, control2: control2)
                    drewSomething = true
                default: return nil
                }
            case .number(let x):
                // SVG repeats the previous command for extra coordinate pairs; a repeated M means L.
                guard let y = scanner.number(), !path.isEmpty else { return nil }
                switch command {
                case "M", "L":
                    path.addLine(to: CGPoint(x: x, y: y))
                    drewSomething = true
                case "C":
                    guard let control2 = scanner.point(), let end = scanner.point() else { return nil }
                    path.addCurve(to: end, control1: CGPoint(x: x, y: y), control2: control2)
                    drewSomething = true
                default: return nil
                }
            }
        }
        return drewSomething ? path.copy() : nil
    }

    /// Splits a path at each move, keeping the order the subpaths were drawn in.
    ///
    /// A move that nothing is drawn from yields no subpath.
    static func subpaths(of path: CGPath) -> [CGPath] {
        var result: [CGPath] = []
        var current = CGMutablePath()
        var drewSomething = false
        func finish() {
            if drewSomething { result.append(current) }
            current = CGMutablePath()
            drewSomething = false
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                finish()
                current.move(to: points[0])
                return
            case .addLineToPoint: current.addLine(to: points[0])
            case .addQuadCurveToPoint: current.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: current.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath: current.closeSubpath()
            @unknown default: return
            }
            drewSomething = true
        }
        finish()
        return result
    }

    private nonisolated enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private nonisolated struct Tokens {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) { characters = Array(text) }

        mutating func next() -> Token? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                return .command(character)
            }
            return number().map(Token.number)
        }

        mutating func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        /// Reads one decimal number. Exponents never appear in generated data.
        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            var sawDigit = false
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isASCII, character.isNumber {
                    sawDigit = true
                } else if character == ".", !sawDot {
                    sawDot = true
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit, let value = Double(String(characters[start..<index])) else {
                index = start
                return nil
            }
            return CGFloat(value)
        }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == "," { index += 1 }
        }
    }
}

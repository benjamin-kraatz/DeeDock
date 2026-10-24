import Foundation

/// An answer with its links to landmarks taken out: the text the person reads, and which runs of
/// it point at something in the window.
///
/// The model links what it mentions as a Markdown link to a landmark's number, such as
/// `[the Send button](#12)`. The link's words stay in the text and become a reference; the syntax
/// goes. A link to a number that is not in the context keeps its words and loses the link, so a
/// made-up number never points at the wrong thing.
///
/// While the answer streams, a link can arrive in pieces. Text from an opening bracket that may
/// still become a link is held back until it either closes as one or turns out not to be, so the
/// card never shows half of the syntax. Once the answer is finished nothing is held back.
nonisolated struct RobiReferencedAnswer: Equatable, Sendable {
    /// A run of `text` that points at a landmark.
    struct Reference: Equatable, Sendable {
        /// Character offsets into `text`.
        let range: Range<Int>
        let landmark: Int
    }

    /// The answer as the person reads, copies and pastes it.
    private(set) var text = ""
    private(set) var references: [Reference] = []

    /// Longest link text accepted. A lone "[" in prose holds back at most this much while streaming.
    static let maximumLabelLength = 200

    /// - Parameters:
    ///   - answer: The model's raw answer, possibly still streaming.
    ///   - landmarks: The numbers a link may point at.
    ///   - isFinished: The answer is complete or stopped, so nothing more can close a link.
    init(_ answer: String, landmarks: Set<Int>, isFinished: Bool) {
        guard answer.contains("](#") || (!isFinished && answer.contains("[")) else {
            text = answer
            return
        }
        let characters = Array(answer)
        var output: [Character] = []
        output.reserveCapacity(characters.count)
        var index = 0
        while index < characters.count {
            guard characters[index] == "[" else {
                output.append(characters[index])
                index += 1
                continue
            }
            switch Self.link(in: characters, at: index) {
            case let .link(label, number, end):
                let start = output.count
                output.append(contentsOf: label)
                if landmarks.contains(number), !label.isEmpty {
                    references.append(Reference(range: start..<output.count, landmark: number))
                }
                index = end
            case .incomplete where !isFinished:
                // Possibly the start of a link that has not fully arrived: hold the rest back.
                index = characters.count
            case .incomplete, .none:
                output.append("[")
                index += 1
            }
        }
        text = String(output)
    }

    private enum Match {
        /// A whole link: its words, its number, and the index just past its closing parenthesis.
        case link(label: ArraySlice<Character>, number: Int, end: Int)
        /// The text ran out while it could still have become a link.
        case incomplete
        /// Not a link.
        case none
    }

    /// Reads `[label](#number)` starting at the bracket at `start`.
    private static func link(in characters: [Character], at start: Int) -> Match {
        var index = start + 1
        while index < characters.count, characters[index] != "]" {
            if characters[index].isNewline || characters[index] == "[" || index - start > maximumLabelLength { return .none }
            index += 1
        }
        let labelEnd = index
        index += 1
        for expected in ["(", "#"] as [Character] {
            guard index < characters.count else { return .incomplete }
            guard characters[index] == expected else { return .none }
            index += 1
        }
        var digits = ""
        while index < characters.count, characters[index].isASCII, characters[index].isNumber, digits.count < 6 {
            digits.append(characters[index])
            index += 1
        }
        guard index < characters.count else { return .incomplete }
        guard characters[index] == ")", let number = Int(digits) else { return .none }
        return .link(label: characters[(start + 1)..<labelEnd], number: number, end: index + 1)
    }
}

/// The link a reference carries in the answer card, and back to the landmark's number.
///
/// The scheme is private to the card: its `openURL` action handles it and nothing is registered
/// with Launch Services, so the link never leaves Robi.
nonisolated enum RobiReferenceLink {
    static let scheme = "x-dokk-robi-landmark"

    static func url(_ landmark: Int) -> URL? { URL(string: "\(scheme):\(landmark)") }

    static func landmark(from url: URL) -> Int? {
        guard url.scheme == scheme else { return nil }
        return Int(url.absoluteString.dropFirst(scheme.count + 1))
    }
}

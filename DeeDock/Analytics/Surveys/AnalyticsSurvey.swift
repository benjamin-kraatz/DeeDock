import Foundation

/// A PostHog survey of type "API", as served by the public `/api/surveys/` endpoint.
///
/// posthog-ios renders surveys on iOS only, so DOKK draws them itself and reports the standard
/// survey events through ``AnalyticsSurveyRecord``. Only the fields DOKK honors are decoded.
/// A survey that needs anything else (a targeting flag, a link question, an "Other" choice with
/// a text field) reports `isSupported == false` and is never shown, rather than shown wrongly.
nonisolated struct AnalyticsSurvey: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let questions: [Question]
    /// The PostHog iteration of a recurring survey. Answers and "seen" state are per iteration.
    let iteration: Int?
    /// Sent back verbatim as `$survey_iteration_start_date`.
    let iterationStartDate: String?
    /// When true, PostHog merges several `survey sent` events with one submission ID, so each
    /// answer can be reported as it is given.
    let partialResponses: Bool
    let appearance: Appearance

    private let type: String
    private let startDate: Date?
    private let endDate: Date?
    private let requiresFlag: Bool

    /// Whether DOKK can render every question and honor every condition.
    var isSupported: Bool {
        type == "api" && !requiresFlag && !questions.isEmpty && questions.allSatisfy(\.isSupported)
    }

    /// Launched and not yet stopped. Drafts have no start date.
    func isRunning(at date: Date) -> Bool {
        guard let startDate, startDate <= date else { return false }
        return endDate.map { date < $0 } ?? true
    }

    /// Identifies this iteration in DOKK's local "already answered" record.
    var seenKey: String { iteration.map { "\(id)/\($0)" } ?? id }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, questions, appearance
        case startDate = "start_date", endDate = "end_date"
        case iteration = "current_iteration", iterationStartDate = "current_iteration_start_date"
        case partialResponses = "enable_partial_responses"
        case linkedFlag = "linked_flag_key", targetingFlag = "targeting_flag_key"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        questions = try container.decode([Question].self, forKey: .questions)
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? Appearance()
        iteration = try container.decodeIfPresent(Int.self, forKey: .iteration)
        iterationStartDate = try container.decodeIfPresent(String.self, forKey: .iterationStartDate)
        partialResponses = try container.decodeIfPresent(Bool.self, forKey: .partialResponses) ?? false
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate).flatMap(Self.date)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate).flatMap(Self.date)
        // PostHog's own `internal_targeting_flag_key` only repeats the "show once" rule DOKK
        // keeps locally, so it is ignored. A flag the author chose is a condition DOKK can't check.
        requiresFlag = try container.decodeIfPresent(String.self, forKey: .linkedFlag) != nil
            || container.decodeIfPresent(String.self, forKey: .targetingFlag) != nil
    }

    /// PostHog writes microseconds (`2026-10-05T07:09:53.211000Z`), which ISO 8601 parsing in
    /// Foundation rejects, so the fraction is dropped before parsing. Second precision is enough
    /// for start and end dates.
    private static func date(_ text: String) -> Date? {
        let trimmed = text.replacing(#/\.\d+/#, with: "")
        return try? Date(trimmed, strategy: .iso8601)
    }
}

// MARK: - Questions

extension AnalyticsSurvey {
    nonisolated struct Question: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let kind: Kind
        let title: String
        let detail: String?
        let isOptional: Bool
        /// The survey author's label for the submit button.
        let buttonText: String?
        let branching: Branching?

        nonisolated enum Kind: Equatable, Sendable {
            case open(TextLimits)
            case singleChoice(Choices)
            case multipleChoice(Choices)
            case rating(Rating)
            /// A link question or a type PostHog added later.
            case unsupported
        }

        var isSupported: Bool {
            switch kind {
            case .open, .rating: true
            case let .singleChoice(choices), let .multipleChoice(choices): !choices.hasOpenChoice && !choices.options.isEmpty
            case .unsupported: false
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id, type, question, description, optional, buttonText, branching
            case choices, shuffleOptions, hasOpenChoice, skipSubmitButton
            case scale, display, lowerBoundLabel, upperBoundLabel, validation
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .question)
            detail = try container.decodeIfPresent(String.self, forKey: .description).flatMap { $0.isEmpty ? nil : $0 }
            isOptional = try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false
            buttonText = try container.decodeIfPresent(String.self, forKey: .buttonText).flatMap { $0.isEmpty ? nil : $0 }
            branching = try container.decodeIfPresent(Branching.self, forKey: .branching)
            let skipsSubmit = try container.decodeIfPresent(Bool.self, forKey: .skipSubmitButton) ?? false

            func choices() throws -> Choices {
                Choices(options: try container.decodeIfPresent([String].self, forKey: .choices) ?? [],
                        shuffles: try container.decodeIfPresent(Bool.self, forKey: .shuffleOptions) ?? false,
                        hasOpenChoice: try container.decodeIfPresent(Bool.self, forKey: .hasOpenChoice) ?? false,
                        submitsOnSelection: skipsSubmit)
            }

            switch try container.decode(String.self, forKey: .type) {
            case "open":
                let rules = try container.decodeIfPresent([ValidationRule].self, forKey: .validation) ?? []
                kind = .open(TextLimits(
                    minimum: rules.first { $0.type == "min_length" }?.value,
                    maximum: rules.first { $0.type == "max_length" }?.value))
            case "single_choice": kind = .singleChoice(try choices())
            case "multiple_choice": kind = .multipleChoice(try choices())
            case "rating":
                let scale = try container.decodeIfPresent(Int.self, forKey: .scale) ?? 5
                let display = try container.decodeIfPresent(String.self, forKey: .display)
                kind = [3, 5, 7, 10].contains(scale)
                    ? .rating(Rating(scale: scale, usesEmoji: display == "emoji" && scale <= 5,
                                     lowerLabel: try container.decodeIfPresent(String.self, forKey: .lowerBoundLabel),
                                     upperLabel: try container.decodeIfPresent(String.self, forKey: .upperBoundLabel),
                                     submitsOnSelection: skipsSubmit))
                    : .unsupported
            default: kind = .unsupported
            }
        }

        private struct ValidationRule: Decodable {
            let type: String
            let value: Int?
        }
    }

    nonisolated struct Choices: Equatable, Sendable {
        let options: [String]
        /// Show the options in a random order, fixed for one submission.
        let shuffles: Bool
        /// The last option asks for free text. DOKK does not render that, see ``Question/isSupported``.
        let hasOpenChoice: Bool
        /// Picking an option answers the question without a submit button (single choice only).
        let submitsOnSelection: Bool
    }

    nonisolated struct Rating: Equatable, Sendable {
        /// 3, 5, 7, or 10. A 10-point scale runs from 0, as an NPS question does.
        let scale: Int
        /// Faces instead of numbers. PostHog offers this for 3- and 5-point scales.
        let usesEmoji: Bool
        let lowerLabel: String?
        let upperLabel: String?
        let submitsOnSelection: Bool

        var values: ClosedRange<Int> { scale == 10 ? 0...10 : 1...scale }
    }

    nonisolated struct TextLimits: Equatable, Sendable {
        let minimum: Int?
        let maximum: Int?

        /// Whether `text`, trimmed, satisfies the author's limits. An empty answer never does;
        /// optional questions offer Skip instead.
        func accepts(_ text: String) -> Bool {
            let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
            return count >= max(1, minimum ?? 1) && count <= (maximum ?? .max)
        }
    }

    /// Where the survey goes after a question. Indexes refer to ``AnalyticsSurvey/questions``.
    nonisolated enum Branching: Decodable, Equatable, Sendable {
        case next
        case end
        case question(Int)
        /// Keyed by choice index ("0", "1", …) for single choice, and by sentiment
        /// ("negative", "neutral", "positive", or "detractors", "passives", "promoters" on a
        /// 10-point scale) for ratings. A response without an entry goes to the next question.
        case byResponse([String: Destination])

        private enum CodingKeys: String, CodingKey { case type, index, responseValues }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "end": self = .end
            case "specific_question": self = .question(try container.decode(Int.self, forKey: .index))
            case "response_based":
                self = .byResponse(try container.decodeIfPresent([String: Destination].self, forKey: .responseValues) ?? [:])
            default: self = .next
            }
        }
    }

    /// A branch target: the literal `"end"` or a question index.
    nonisolated enum Destination: Decodable, Equatable, Sendable {
        case end
        case question(Int)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) { self = .question(index) }
            else if try container.decode(String.self) == "end" { self = .end }
            else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown branch target") }
        }
    }

    /// The author's thank-you message. DOKK supplies its own copy when a field is empty.
    nonisolated struct Appearance: Decodable, Equatable, Sendable {
        var showsThankYou = true
        var thankYouTitle: String?
        var thankYouMessage: String?
        var thankYouButton: String?
        /// The thank-you message closes by itself after a few seconds.
        var closesAutomatically = false

        private enum CodingKeys: String, CodingKey {
            case showsThankYou = "displayThankYouMessage", thankYouTitle = "thankYouMessageHeader"
            case thankYouMessage = "thankYouMessageDescription", thankYouButton = "thankYouMessageCloseButtonText"
            case closesAutomatically = "autoDisappear"
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ key: CodingKeys) throws -> String? {
                try container.decodeIfPresent(String.self, forKey: key).flatMap { $0.isEmpty ? nil : $0 }
            }
            showsThankYou = try container.decodeIfPresent(Bool.self, forKey: .showsThankYou) ?? true
            thankYouTitle = try text(.thankYouTitle)
            thankYouMessage = try text(.thankYouMessage)
            thankYouButton = try text(.thankYouButton)
            closesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .closesAutomatically) ?? false
        }
    }
}

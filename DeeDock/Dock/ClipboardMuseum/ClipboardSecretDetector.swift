import Foundation

/// The kind of secret a clip appears to contain.
nonisolated enum ClipboardSecretKind: String, Codable, CaseIterable, Sendable {
    case privateKey
    case accessToken
    case webToken
    case cardNumber
    case credential
    case generatedSecret
}

/// Local, pattern-based secret detection. Nothing leaves the Mac.
///
/// The detector favors well-known shapes (PEM keys, vendor token prefixes, JWTs, Luhn-valid card
/// numbers, `password=` assignments) and one conservative heuristic for generated passwords. It
/// can miss secrets; password managers that mark their copies as concealed are handled earlier,
/// by never reading those items at all.
nonisolated enum ClipboardSecretDetector {
    /// Vendor token shapes: AWS, GitHub, Slack, Stripe, OpenAI/Anthropic-style `sk-`, Google, GitLab.
    static let tokenPatterns = [
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bgh[pousr]_[A-Za-z0-9]{36,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{22,}"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\b[rs]k_(live|test)_[A-Za-z0-9]{16,}"#,
        #"\bsk-[A-Za-z0-9_-]{20,}"#,
        #"\bAIza[0-9A-Za-z_-]{35}\b"#,
        #"\bglpat-[A-Za-z0-9_-]{20,}"#,
    ]

    static func detect(_ text: String) -> ClipboardSecretKind? {
        let sample = String(text.prefix(ClipboardMuseumLimits.maximumTextCharacters))
        if matches(sample, #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"#) { return .privateKey }
        if tokenPatterns.contains(where: { matches(sample, $0) }) { return .accessToken }
        if matches(sample, #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#) { return .webToken }
        if cardDigits(in: sample) != nil { return .cardNumber }
        if matches(sample, #"(?i)\b(password|passwd|pwd|passcode|secret|api[_-]?key|access[_-]?token|client[_-]?secret)\b\s*[:=]\s*\S{4,}"#) {
            return .credential
        }
        if looksGenerated(sample) { return .generatedSecret }
        return nil
    }

    /// Identification that is safe to keep after redaction: a token's vendor prefix or a card's
    /// last four digits. Everything else gets no hint.
    static func hint(for text: String, secret: ClipboardSecretKind) -> String? {
        switch secret {
        case .cardNumber:
            return cardDigits(in: text).map { "•••• " + $0.suffix(4) }
        case .accessToken:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains(where: \.isWhitespace) else { return nil }
            if trimmed.hasPrefix("AKIA") { return "AKIA••••" }
            let head = trimmed.prefix(12)
            guard let separator = head.firstIndex(where: { $0 == "_" || $0 == "-" }) else { return nil }
            return String(trimmed[...separator]) + "••••"
        case .privateKey, .webToken, .credential, .generatedSecret:
            return nil
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Digits of the first run that looks like a payment card: 13–19 Luhn-valid digits written
    /// either solid or in the grouping cards print (4-4-4-4, or 4-6-5).
    static func cardDigits(in text: String) -> String? {
        var runs: [[Substring]] = []
        var current: [Substring] = []
        for part in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "-" }) {
            if !part.isEmpty, part.allSatisfy(\.isASCIIDigitCharacter) {
                current.append(part)
            } else {
                // A run ends at non-digit text; digits glued to letters never count.
                if !current.isEmpty { runs.append(current) }
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        for groups in runs {
            let digits = groups.joined()
            guard (13...19).contains(digits.count), Set(digits).count > 1, isCardGrouping(groups.map(\.count)),
                  passesLuhn(String(digits)) else { continue }
            return String(digits)
        }
        return nil
    }

    private static func isCardGrouping(_ lengths: [Int]) -> Bool {
        if lengths.count == 1 { return true }
        if lengths == [4, 6, 5] || lengths == [4, 6, 4] { return true }
        return lengths.dropLast().allSatisfy { $0 == 4 } && (1...4).contains(lengths.last ?? 0)
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if offset.isMultiple(of: 2) == false {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum.isMultiple(of: 10)
    }

    /// A single unbroken token that mixes lowercase, uppercase, and digits and switches between
    /// them often. CamelCase words and dates switch rarely, so they stay clear; hex hashes and
    /// UUIDs lack uppercase and stay clear too.
    static func looksGenerated(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(token.count), !token.contains(where: \.isWhitespace),
              !token.contains("://"), !token.hasPrefix("/"), !token.hasPrefix("~") else { return false }
        func category(_ character: Character) -> Int {
            if character.isLowercase { return 0 }
            if character.isUppercase { return 1 }
            if character.isNumber { return 2 }
            return 3
        }
        let categories = token.map(category)
        guard Set(categories).isSuperset(of: [0, 1, 2]) else { return false }
        let switches = zip(categories, categories.dropFirst()).filter { $0 != $1 }.count
        return Double(switches) >= Double(token.count - 1) * 0.4
    }
}

private extension Character {
    nonisolated var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}

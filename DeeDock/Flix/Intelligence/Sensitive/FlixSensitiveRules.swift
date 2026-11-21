import Foundation

/// What a sensitive file shows.
nonisolated enum FlixSensitiveKind: String, Codable, Sendable {
    /// A passport, ID card, or driving licence.
    case identity
    /// An IBAN, account and routing numbers, or a card.
    case bank
    /// A private key, a certificate bundle, or a password store.
    case secret

    /// The row's and the dialog's reason ("Looks like an ID document").
    var reason: String {
        switch self {
        case .identity: String(localized: .flixSensitiveReasonIdentity)
        case .bank: String(localized: .flixSensitiveReasonBank)
        case .secret: String(localized: .flixSensitiveReasonSecret)
        }
    }
}

/// The text and name rules of the sensitive file guard. Pure, so they are tested directly.
///
/// - **IDs**: a machine-readable zone line (`P<`, `ID`, `I<` followed by `<` fillers, 30–44
///   characters), or two of the ID words ("passport", "date of birth", "nationality", "Reisepass",
///   "Personalausweis", "Staatsangehörigkeit", …). One word alone is common in ordinary mail.
/// - **Bank details**: an IBAN that passes its mod-97 check, or two of the bank words ("account
///   number", "routing number", "sort code", "BIC", "SWIFT", "Kontonummer", "BLZ", …), or a card
///   number that passes the Luhn check next to "card".
/// - **Secrets**: PEM blocks (`-----BEGIN … PRIVATE KEY-----`, `BEGIN CERTIFICATE`), OpenSSH and PGP
///   private keys, and files whose extension is a key or password store (`.pem`, `.key`, `.p12`,
///   `.pfx`, `.kdbx`, `.keychain-db`, `.ovpn`, `.asc`, `.gpg`, `.ppk`…) or whose name is a password
///   file (`passwords.txt`, `id_rsa`, `.env`).
nonisolated enum FlixSensitiveRules {
    static let secretExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "p8", "der", "kdbx", "kdb", "keychain", "keychain-db", "1pif", "1pux",
        "ovpn", "asc", "gpg", "pgp", "ppk", "jks", "keystore", "mobileprovision", "cer", "crt",
    ]
    static let secretNames: Set<String> = ["id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".env", ".netrc", ".pgpass",
                                           "credentials", "credentials.json", "service-account.json"]
    static let secretNameWords = ["password", "passwords", "passwort", "passwörter", "kennwort", "recovery codes",
                                  "recovery-codes", "backup codes", "wiederherstellungscode", "seed phrase", "private key"]
    static let identityWords = [
        "passport", "date of birth", "nationality", "place of birth", "date of expiry", "identity card",
        "driving licence", "driver license", "driver's license", "surname", "given names",
        "reisepass", "personalausweis", "staatsangehörigkeit", "geburtsdatum", "geburtsort", "gültig bis",
        "führerschein", "aufenthaltstitel", "passeport", "nationalité", "carte d'identité",
    ]
    static let bankWords = [
        "iban", "bic", "swift", "account number", "routing number", "sort code", "account holder",
        "kontonummer", "bankleitzahl", "blz", "kontoinhaber", "card number", "cvv", "kartennummer",
    ]

    /// The verdict from a file's name alone, before anything is read.
    static func kind(forFileName name: String) -> FlixSensitiveKind? {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        if secretExtensions.contains(ext) || secretNames.contains(lower) { return .secret }
        if secretNameWords.contains(where: lower.contains) { return .secret }
        return nil
    }

    /// The verdict from text read out of a file (its contents, a PDF's text, or OCR of a picture).
    static func kind(forText text: String) -> FlixSensitiveKind? {
        guard !text.isEmpty else { return nil }
        if containsSecretMarker(text) { return .secret }
        if containsMRZ(text) { return .identity }
        let lower = text.lowercased()
        if identityWords.filter({ lower.contains($0) }).count >= 2 { return .identity }
        if containsValidIBAN(text) { return .bank }
        if bankWords.filter({ containsWord($0, in: lower) }).count >= 2 { return .bank }
        if lower.contains("card"), containsCardNumber(text) { return .bank }
        return nil
    }

    static func containsSecretMarker(_ text: String) -> Bool {
        let markers = ["PRIVATE KEY-----", "BEGIN CERTIFICATE-----", "BEGIN OPENSSH PRIVATE KEY",
                       "BEGIN PGP PRIVATE KEY BLOCK", "PuTTY-User-Key-File", "BEGIN ENCRYPTED PRIVATE KEY"]
        return markers.contains(where: text.contains)
    }

    /// A passport or ID card's machine-readable zone: a line of capitals, digits, and `<` fillers.
    static func containsMRZ(_ text: String) -> Bool {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: " ", with: "").uppercased()
            guard line.count >= 28, line.count <= 46 else { continue }
            let fillers = line.filter { $0 == "<" }.count
            guard fillers >= 3, line.allSatisfy({ $0 == "<" || ($0.isASCII && ($0.isUppercase || $0.isNumber)) }) else { continue }
            if line.hasPrefix("P<") || line.hasPrefix("ID") || line.hasPrefix("I<") || line.hasPrefix("A<")
                || line.hasPrefix("C<") || line.hasPrefix("V<") || line.contains("<<") {
                return true
            }
        }
        return false
    }

    /// An IBAN (country code, two check digits, 11–30 more characters, spaces allowed) that passes
    /// the ISO 13616 mod-97 check, so order numbers that look alike do not count.
    static func containsValidIBAN(_ text: String) -> Bool {
        let pattern = #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{2,4}){3,8}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let upper = text.uppercased()
        for match in regex.matches(in: upper, range: NSRange(upper.startIndex..., in: upper)) {
            guard let range = Range(match.range, in: upper) else { continue }
            // The match may run into the next word ("… 0130 00 BY FRIDAY"): try it whole, then
            // without its last space-separated groups.
            var groups = upper[range].split(separator: " ")
            while groups.joined().count >= 15 {
                if isValidIBAN(groups.joined()) { return true }
                groups.removeLast()
            }
        }
        return false
    }

    static func isValidIBAN(_ candidate: String) -> Bool {
        let compact = candidate.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.count >= 15, compact.count <= 34 else { return false }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            if let digit = character.wholeNumberValue {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = character.asciiValue, character.isLetter {
                let value = Int(ascii) - 55
                remainder = (remainder * 100 + value) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }

    /// A 13–19 digit number passing the Luhn check.
    static func containsCardNumber(_ text: String) -> Bool {
        let pattern = #"\b(?:\d[ -]?){12,18}\d\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let digits = text[range].compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count) else { continue }
            var sum = 0
            for (index, digit) in digits.reversed().enumerated() {
                if index % 2 == 1 { let doubled = digit * 2; sum += doubled > 9 ? doubled - 9 : doubled } else { sum += digit }
            }
            if sum % 10 == 0 { return true }
        }
        return false
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        guard word.count <= 4 else { return text.contains(word) }
        // Short words ("bic", "blz", "cvv") only as whole words.
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

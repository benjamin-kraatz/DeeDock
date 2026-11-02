import Foundation

/// One line of an App Health file: the envelope every record shares (`v`, `type`, `ts`) plus its body's fields,
/// flattened into the same JSON object.
///
/// Encoding writes the envelope keys and then lets the body encode into the same keyed container, which
/// `JSONEncoder` merges into one object. Decoding reads `type` first and decodes the matching body from the same
/// object; unknown keys are ignored, so a newer reader can still read version 1.
nonisolated struct AppHealthRecord: Codable, Sendable, Equatable {
    /// Bump when a field changes meaning or a required field is added.
    static let schemaVersion = 1

    enum Body: Sendable, Equatable {
        case tick(AppHealthTickRecord)
        case sample(AppHealthSampleRecord)
        case event(AppHealthEventRecord)
        case prompt(AppHealthPromptRecord)
        case label(AppHealthLabelRecord)
    }

    let timestamp: Date
    let body: Body

    init(_ body: Body, at timestamp: Date) {
        self.body = body
        self.timestamp = timestamp
    }

    /// The `type` field.
    var type: String {
        switch body {
        case .tick: "tick"
        case .sample: "sample"
        case .event: "event"
        case .prompt: "prompt"
        case .label: "label"
        }
    }

    private enum EnvelopeKeys: String, CodingKey {
        case v, type, ts
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeKeys.self)
        try container.encode(Self.schemaVersion, forKey: .v)
        try container.encode(type, forKey: .type)
        try container.encode(AppHealthRounding.timestamp(timestamp), forKey: .ts)
        switch body {
        case .tick(let record): try record.encode(to: encoder)
        case .sample(let record): try record.encode(to: encoder)
        case .event(let record): try record.encode(to: encoder)
        case .prompt(let record): try record.encode(to: encoder)
        case .label(let record): try record.encode(to: encoder)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeKeys.self)
        timestamp = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .ts))
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "tick": body = .tick(try AppHealthTickRecord(from: decoder))
        case "sample": body = .sample(try AppHealthSampleRecord(from: decoder))
        case "event": body = .event(try AppHealthEventRecord(from: decoder))
        case "prompt": body = .prompt(try AppHealthPromptRecord(from: decoder))
        case "label": body = .label(try AppHealthLabelRecord(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container,
                                                   debugDescription: "Unknown App Health record type")
        }
    }

    /// The encoder every App Health writer uses: one compact line per record, slashes unescaped.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

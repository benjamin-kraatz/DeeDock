import FoundationModels
import Observation
import Foundation

@Generable(description: "Two sRGB hexadecimal colors for gentle ambient lighting")
private struct AtmosphereMoodResponse {
    @Guide(description: "First color as exactly six hexadecimal digits, without #") var first: String
    @Guide(description: "Second color as exactly six hexadecimal digits, without #") var second: String
}

/// Each Apply owns one generation. Source changes and pane dismissal cancel pending work.
@MainActor @Observable
final class AtmosphereMood {
    var available: Bool { SystemLanguageModel.default.availability == .available }
    private(set) var generating = false
    private(set) var failed = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func apply(to store: AtmosphereStore) {
        cancel()
        guard available else { return }
        let mood = store.settings.mood
        guard !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generating = true; failed = false
        task = Task { [weak self, weak store] in
            do {
                let session = LanguageModelSession(instructions: "Create a harmonious two-color ambient palette matching the user's mood. Return only colors.")
                let result = try await session.respond(to: String(mood.prefix(500)), generating: AtmosphereMoodResponse.self)
                try Task.checkCancellation()
                guard let store, store.settings.source == .mood, store.settings.mood == mood else {
                    self?.generating = false
                    return
                }
                guard let first = Self.parse(result.content.first), let second = Self.parse(result.content.second) else {
                    self?.failed = true
                    self?.generating = false
                    return
                }
                store.settings.moodPalette = .init(first: first, second: second)
            } catch {
                if !Task.isCancelled { self?.failed = true }
            }
            if !Task.isCancelled { self?.generating = false }
        }
    }

    func cancel() { task?.cancel(); task = nil; generating = false }

    private static func parse(_ value: String) -> AtmosphereColor? {
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "# \n"))
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        return .init(Double((rgb >> 16) & 255) / 255, Double((rgb >> 8) & 255) / 255, Double(rgb & 255) / 255)
    }
}

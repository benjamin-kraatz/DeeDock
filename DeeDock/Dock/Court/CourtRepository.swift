import Foundation
import Observation

/// Versioned local fiction. Unreadable bytes remain untouched until explicit Clear court data.
@MainActor @Observable
final class CourtRepository {
    private(set) var document = CourtDocument()
    private(set) var unavailable = false
    @ObservationIgnored private let defaults: UserDefaults?
    private let key = "court.experiment.v1"

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: key) {
            do {
                let saved = try JSONDecoder().decode(CourtDocument.self, from: data)
                guard saved.version == 1 else { unavailable = true; return }
                document = saved
            } catch { unavailable = true }
        }
    }

    func update(_ edit: (inout CourtDocument) -> Void) {
        guard !unavailable else { return }
        var next = document
        edit(&next)
        do {
            let bytes = try JSONEncoder().encode(next)
            defaults?.set(bytes, forKey: key)
            document = next
        } catch { unavailable = true }
    }

    func clear() {
        defaults?.removeObject(forKey: key)
        document = CourtDocument()
        unavailable = false
    }
}

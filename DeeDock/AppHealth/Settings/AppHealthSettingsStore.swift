import Foundation
import Observation

/// App Health's two switches, persisted as JSON under `appHealth.settings.v1`. Both are off by default.
///
/// Only `AppHealthController` changes them, so turning collection on or off and starting or stopping the
/// collector stay one step. Every change is reported to analytics as a feature setting; the values themselves
/// carry no app identity.
@MainActor @Observable
final class AppHealthSettingsStore {
    /// The stored document. Unknown or missing keys decode as off.
    nonisolated struct Settings: Codable, Equatable, Sendable {
        var collecting = false
        var labelling = false

        init(collecting: Bool = false, labelling: Bool = false) {
            self.collecting = collecting
            self.labelling = labelling
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            collecting = try container.decodeIfPresent(Bool.self, forKey: .collecting) ?? false
            labelling = try container.decodeIfPresent(Bool.self, forKey: .labelling) ?? false
        }
    }

    static let defaultsKey = "appHealth.settings.v1"

    /// Whether App Health samples apps and writes records.
    private(set) var collecting: Bool
    /// Whether labelling prompts may appear. Inert while `collecting` is off, but kept.
    private(set) var labelling: Bool
    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameter defaults: Nil for an in-memory store, as previews and tests use.
    init(defaults: UserDefaults?, initial: Settings = Settings()) {
        self.defaults = defaults
        let stored = defaults?.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        let settings = stored ?? initial
        collecting = settings.collecting
        labelling = settings.labelling
    }

    func setCollecting(_ value: Bool) {
        guard value != collecting else { return }
        Analytics.shared.featureSettingChanged(.appHealthEnabled, from: AnalyticsValue(collecting),
                                               to: AnalyticsValue(value))
        collecting = value
        save()
    }

    func setLabelling(_ value: Bool) {
        guard value != labelling else { return }
        Analytics.shared.featureSettingChanged(.appHealthLabelling, from: AnalyticsValue(labelling),
                                               to: AnalyticsValue(value))
        labelling = value
        save()
    }

    private func save() {
        guard let defaults,
              let data = try? JSONEncoder().encode(Settings(collecting: collecting, labelling: labelling)) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

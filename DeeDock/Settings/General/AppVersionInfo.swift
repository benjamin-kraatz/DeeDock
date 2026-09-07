import Foundation

/// Version values come from the built product, so Settings and update messages never duplicate
/// `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in source code.
struct AppVersionInfo: Equatable {
    let version: String
    let build: String?

    static let current = AppVersionInfo(bundle: .main)

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    var settingsValue: String {
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

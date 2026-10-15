import Foundation

/// Which folder the query service loads the text model from.
///
/// The installed folder (`ModelFiles.installed`, where the app puts its download) wins whenever it holds the text
/// model. Only without it does the service look at a development override, so a stale override can't hide a real
/// install: the `LOOKOUT_MODELS` environment variable, then the `LookoutModelsFolder` default in the service's own
/// defaults domain (`defaults write <app identifier>.LookoutQueryService LookoutModelsFolder <folder>`). XPC services
/// don't inherit the app's environment, so the default is the practical override for a service launched by the app.
enum QueryModelLocation {
    static let environmentKey = "LOOKOUT_MODELS"
    static let defaultsKey = "LookoutModelsFolder"

    /// The folder to load from. Without a usable override this is the installed folder, even when it's empty, so the
    /// missing-model error names the place the app downloads to.
    static func folder(environment: [String: String] = ProcessInfo.processInfo.environment,
                       defaults: UserDefaults = .standard) -> URL {
        let installed = ModelFiles.installed
        if FileManager.default.fileExists(atPath: installed.appendingPathComponent(ModelFiles.text.name).path) {
            return installed
        }
        if let path = environment[environmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = defaults.string(forKey: defaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return installed
    }
}

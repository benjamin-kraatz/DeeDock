import SwiftUI

/// Field bindings preserve inheritance: editing a value creates only that field's display override.
struct SettingsValueSource {
    let store: DockSettingsStore
    var profiles: DisplayProfilesStore? = nil
    let context: SettingsOverrideContext?
    var value: DockSettings {
        if let context { return context.profiles.effectiveSettings(for: context.id) }
        return profiles?.effectiveDefaultSettings ?? store.value
    }
    var activeModeName: String? { (context?.profiles ?? profiles)?.modes.activeMode.name }
    var modeSettingsAvailable: Bool { (context?.profiles ?? profiles)?.modes.canEdit ?? true }
    func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        Binding(get: { value[keyPath: keyPath] }, set: { proposed in
            if let context { context.profiles.update(context.id, keyPath: keyPath, to: proposed) }
            else { store.update(keyPath, to: proposed) }
        })
    }

    func appVisibilityBinding() -> Binding<DockAppVisibility> {
        Binding(get: { value.appVisibility }, set: { proposed in
            if let context { context.profiles.update(context.id, keyPath: \.appVisibility, to: proposed) }
            else if let profiles { profiles.updateDefaultVisibility(proposed) }
            else { store.update(\.appVisibility, to: proposed) }
        })
    }

    /// Window Peek is app-wide, so a preset always writes the shared settings.
    func apply(_ preset: WindowPeekPreset) {
        store.update { preset.apply(to: &$0) }
    }
}

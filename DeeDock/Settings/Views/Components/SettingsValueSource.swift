import SwiftUI

/// Field bindings preserve inheritance: editing a value creates only that field's display override.
struct SettingsValueSource {
    let store: DockSettingsStore
    let context: SettingsOverrideContext?
    var value: DockSettings {
        if let context { return context.profiles.effectiveSettings(for: context.id) }
        return store.value
    }
    func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        Binding(get: { value[keyPath: keyPath] }, set: { proposed in
            if let context { context.profiles.update(context.id, keyPath: keyPath, to: proposed) }
            else { store.update(keyPath, to: proposed) }
        })
    }

    /// Window Peek is app-wide, so a preset always writes the shared settings.
    func apply(_ preset: WindowPeekPreset) {
        store.update { preset.apply(to: &$0) }
    }
}

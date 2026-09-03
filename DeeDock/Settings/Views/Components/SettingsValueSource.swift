import SwiftUI

/// Field bindings preserve inheritance: editing a value creates only that field's display override.
struct SettingsValueSource {
    let store: DockSettingsStore
    let context: SettingsOverrideContext?
    var value: DockSettings { context.map { $0.profiles.effectiveSettings(for: $0.id) } ?? store.value }
    func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        Binding(get: { value[keyPath: keyPath] }, set: { proposed in
            if let context { context.profiles.update(context.id, keyPath: keyPath, to: proposed) }
            else { store.update(keyPath, to: proposed) }
        })
    }
}

import SwiftUI

/// Routes one display's explicit overrides without coupling reusable controls to persistence.
struct SettingsOverrideContext {
    let profiles: DisplayProfilesStore
    let id: String
}

private struct SettingsOverrideModifier: ViewModifier {
    let context: SettingsOverrideContext?
    let field: DockSettingField

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            if let context {
                let overridden = context.profiles.document.profiles[context.id]?.overrides.contains(field) == true
                HStack {
                    Text(overridden ? .displayCustomized : .displayFollowingDefault)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if overridden {
                        Button(.displayUseDefault) { context.profiles.useDefault(field, for: context.id) }
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }
}

extension View {
    /// Adds inheritance status and an individual reset action only in display-specific panes.
    func settingsOverride(_ context: SettingsOverrideContext?, field: DockSettingField) -> some View {
        modifier(SettingsOverrideModifier(context: context, field: field))
    }
}

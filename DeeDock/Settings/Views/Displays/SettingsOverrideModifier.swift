import SwiftUI

/// Routes one display's explicit overrides without coupling reusable controls to persistence.
struct SettingsOverrideContext {
    let profiles: DisplayProfilesStore
    let id: String
}

private struct SettingsOverrideModifier: ViewModifier {
    let context: SettingsOverrideContext?
    let field: DockSettingField
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOverridden: Bool {
        guard let context else { return false }
        if field == .appVisibility { return context.profiles.hasModeVisibilityOverride(for: context.id) }
        return context.profiles.document.profiles[context.id]?.overrides.contains(field) == true
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            // An inherited value is the quiet default, so only a customized row explains itself.
            if let context, isOverridden {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(.displayCustomized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(.displayUseDefault) { context.profiles.useDefault(field, for: context.id) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(.horizontal, SettingsMetrics.rowInset)
                .padding(.bottom, 9)
            }
        }
        // A faint tint of the pane color marks the rows this display no longer inherits.
        .background(isOverridden ? AnyShapeStyle(.tint.opacity(0.06)) : AnyShapeStyle(.clear))
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isOverridden)
    }
}

extension View {
    /// Adds inheritance status and an individual reset action only in display-specific panes.
    func settingsOverride(_ context: SettingsOverrideContext?, field: DockSettingField) -> some View {
        modifier(SettingsOverrideModifier(context: context, field: field))
    }
}

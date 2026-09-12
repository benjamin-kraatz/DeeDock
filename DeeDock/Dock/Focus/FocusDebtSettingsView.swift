import SwiftUI

/// Explains what constitutes a promise before the user opts into local counting.
struct FocusDebtSettingsView: View {
    let controller: FocusSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(.focusDebtEnable, isOn: Binding(
                get: { controller.focusDebt.enabled },
                set: { controller.configureFocusDebt(enabled: $0) }
            ))
            .disabled(controller.requiresReset)
            Text(.focusDebtHelp).font(.callout).foregroundStyle(.secondary)
            if controller.focusDebt.enabled {
                FocusDebtStatusView(count: controller.focusDebt.count) {
                    controller.configureFocusDebt(enabled: false)
                }
            }
        }
    }
}

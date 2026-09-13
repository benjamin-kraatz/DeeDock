import SwiftUI

/// Defaults affect the next session; changing them never resets an active deadline.
struct FocusSessionSettingsCard: View {
    let controller: FocusSessionController
    @State private var confirmsReset = false

    private var defaultMinutes: Int { FocusSessionsDocument().minutes }
    private var minutes: Binding<Int> {
        Binding(get: { controller.document.minutes }, set: { controller.configure(minutes: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            sessionCard
            SettingsCard(title: .focusTitle, footnote: .focusSettingsHelp) {
                SettingsRow(title: .focusDurationTitle) {
                    HStack(spacing: 6) {
                        if controller.document.minutes != defaultMinutes {
                            SettingsResetButton(title: .focusDurationTitle) {
                                controller.configure(minutes: defaultMinutes)
                            }
                        }
                        Text(.focusDurationValue(controller.document.minutes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper(value: minutes, in: 1...180) { Text(.focusDurationTitle) }
                            .labelsHidden()
                    }
                }
                .disabled(controller.requiresReset)
                SettingsToggleRow(title: .focusCelebrate,
                                  isOn: Binding(get: { controller.document.celebrates },
                                                set: { controller.configure(celebrates: $0) }),
                                  disabled: controller.requiresReset)
                if let error = controller.error {
                    SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                      message: Text(verbatim: error))
                }
                if controller.requiresReset {
                    SettingsActionRow {
                        Button(.focusReset, role: .destructive) { confirmsReset = true }
                    }
                }
            }
            BossFightSettingsView(controller: controller)
        }
        .confirmationDialog(.focusReset, isPresented: $confirmsReset) {
            Button(.focusReset, role: .destructive) { controller.reset() }
        } message: { Text(.focusResetHelp) }
    }

    /// The running timer, when there is one: its mode, the primary control, and the rest in a menu.
    @ViewBuilder private var sessionCard: some View {
        if let session = controller.session {
            SettingsCard {
                SettingsRow(title: .focusCurrentMode(session.modeName)) {
                    HStack(spacing: 8) {
                        switch session.phase {
                        case .running: Button(.focusPause) { controller.pause() }
                        case .paused: Button(.focusResume) { controller.resume() }
                        default: Button(.focusDismiss) { controller.dismiss() }
                        }
                        if session.phase != .completed {
                            SettingsMoreMenu {
                                Button(.focusExtend) { controller.extend() }.disabled(session.duration > 86100)
                                Button(.focusFinish) { controller.finish() }
                                Divider()
                                Button(.bossFightCancelSession, role: .destructive) { controller.dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Focus defaults") {
    ScrollView {
        FocusSessionSettingsCard(controller: FocusSessionController(defaults: UserDefaults(suiteName: "FocusSettingsPreview")!))
            .padding(24)
    }
    .frame(width: 640, height: 600)
}
#endif

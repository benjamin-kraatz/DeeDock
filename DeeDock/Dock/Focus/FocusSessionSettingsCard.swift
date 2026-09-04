import SwiftUI

/// Defaults affect the next session; changing them never resets an active deadline.
struct FocusSessionSettingsCard: View {
    let controller: FocusSessionController
    @State private var confirmsReset = false

    var body: some View {
        SettingsCard(title: .focusTitle, footnote: .focusSettingsHelp) {
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 12) {
                    Stepper(value: Binding(get: { controller.document.minutes },
                                           set: { controller.configure(minutes: $0) }), in: 1...180) {
                        Text(.focusDuration(controller.document.minutes))
                    }.disabled(controller.requiresReset)
                    Toggle(.focusCelebrate, isOn: Binding(get: { controller.document.celebrates },
                                                         set: { controller.configure(celebrates: $0) }))
                        .disabled(controller.requiresReset)
                    if let session = controller.session {
                        Text(.focusCurrentMode(session.modeName)).font(.callout)
                        if session.phase == .running { Button(.focusPause) { controller.pause() } }
                        else if session.phase == .paused { Button(.focusResume) { controller.resume() } }
                        else { Button(.focusDismiss) { controller.dismiss() } }
                        if session.phase != .completed {
                            HStack {
                                Button(.focusExtend) { controller.extend() }.disabled(session.duration > 86100)
                                Button(.focusFinish) { controller.finish() }
                            }
                        }
                    }
                    if let error = controller.error { Text(verbatim: error).foregroundStyle(.red) }
                    if controller.requiresReset {
                        Button(.focusReset, role: .destructive) { confirmsReset = true }
                    }
                }
            }
        }
        .confirmationDialog(.focusReset, isPresented: $confirmsReset) {
            Button(.focusReset, role: .destructive) { controller.reset() }
        } message: { Text(.focusResetHelp) }
    }
}

#if DEBUG
#Preview("Focus defaults") {
    FocusSessionSettingsCard(controller: FocusSessionController(defaults: UserDefaults(suiteName: "FocusSettingsPreview")!))
        .padding().frame(width: 620)
}
#endif

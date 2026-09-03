import SwiftUI

/// The closing page: the three things worth knowing, and the one setting worth offering.
///
/// Launch at login is the single control the tour writes, and it reuses the Settings pane's own
/// `LoginItemSettingsCard`, so approval, cancellation, and error recovery behave identically in
/// both places. Everything else on this page is a pointer to where a person goes next.
struct OnboardingFinalStep: View {
    let loginStatus: LoginItemStatus
    var pendingOperation: LoginItemController.Operation?
    var loginError: LocalizedStringResource?
    var setLoginEnabled: (Bool) -> Void = { _ in }
    var cancelLoginRequest: () -> Void = {}
    var refreshLogin: () -> Void = {}
    var openLoginSettings: () -> Void = {}
    var dismissLoginError: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                hint(symbol: "arrow.down.doc.fill", text: .onboardingReadyPinning)
                hint(symbol: "menubar.arrow.up.rectangle", text: .onboardingReadyMenuBar)
                hint(symbol: "keyboard", text: .onboardingReadyKeyboard)
            }
            LoginItemSettingsCard(status: loginStatus, pendingOperation: pendingOperation,
                                  errorMessage: loginError,
                                  setEnabled: setLoginEnabled, cancelRequest: cancelLoginRequest,
                                  refresh: refreshLogin, openSettings: openLoginSettings,
                                  dismissError: dismissLoginError)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(symbol: String, text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStep.ready.tint)
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Final step") {
    OnboardingFinalStep(loginStatus: .notRegistered).padding(28).frame(width: 700)
}

#Preview("Final step — approval pending, dark") {
    OnboardingFinalStep(loginStatus: .requiresApproval, pendingOperation: .register)
        .padding(28).frame(width: 700).preferredColorScheme(.dark)
}
#endif

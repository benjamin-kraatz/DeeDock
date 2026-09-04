import SwiftUI

/// Value-driven presentation keeps every preview independent of real login registration.
struct LoginItemSettingsCard: View {
    let status: LoginItemStatus
    var pendingOperation: LoginItemController.Operation?
    var errorMessage: LocalizedStringResource?
    var setEnabled: (Bool) -> Void = { _ in }
    var cancelRequest: () -> Void = {}
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}
    var dismissError: () -> Void = {}

    private var isPending: Bool { pendingOperation != nil }

    var body: some View {
        SettingsCard {
            SettingsRow(title: .loginLaunchAtLogin, subtitle: status.message) {
                Toggle(isOn: Binding(get: { status.isEnabled }, set: setEnabled)) {
                    Text(.loginLaunchAtLogin)
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isPending || !status.canToggle)
                .accessibilityHint(Text(.loginToggleHint))
            }

            if let pendingOperation {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(pendingOperation.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SettingsMetrics.rowInset)
                .padding(.vertical, 10)
                .accessibilityAddTraits(.updatesFrequently)
            }

            if status == .requiresApproval {
                SettingsActionRow { approvalActions }
            } else if status == .notFound || status == .unknown {
                SettingsActionRow { recoveryActions }
            }

            if let errorMessage {
                SettingsInlineError(message: errorMessage, dismiss: dismissError)
            }
        }
    }

    @ViewBuilder private var approvalActions: some View {
        Button(.loginCancelRequest, action: cancelRequest).disabled(isPending)
        Button(.loginOpenSystemSettings, action: openSettings).buttonStyle(.borderedProminent)
    }

    @ViewBuilder private var recoveryActions: some View {
        Button(.loginRefresh, action: refresh).disabled(isPending)
        Button(.loginOpenSystemSettings, action: openSettings).buttonStyle(.borderedProminent)
    }
}

private extension LoginItemStatus {
    var message: LocalizedStringResource {
        switch self {
        case .notRegistered: .loginStatusOff
        case .enabled: .loginStatusEnabled
        case .requiresApproval: .loginStatusRequiresApproval
        case .notFound: .loginStatusNotFound
        case .unknown: .loginStatusUnknown
        }
    }
}

private extension LoginItemController.Operation {
    var message: LocalizedStringResource {
        switch self {
        case .register: .loginRegistering
        case .unregister: .loginUnregistering
        case .cancelRequest: .loginCancelling
        }
    }
}

#if DEBUG
#Preview("Login registration states") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(LoginItemStatus.allCases, id: \.self) { status in
                LoginItemSettingsCard(status: status)
            }
        }.padding()
    }.frame(width: 530, height: 700)
}

#Preview("Pending requests — opaque, static feedback") {
    VStack(spacing: 20) {
        LoginItemSettingsCard(status: .notRegistered, pendingOperation: .register)
        LoginItemSettingsCard(status: .enabled, pendingOperation: .unregister)
        LoginItemSettingsCard(status: .requiresApproval, pendingOperation: .cancelRequest)
    }
    .padding().frame(width: 530)
}

#Preview("Long error — dark, narrow, large text") {
    LoginItemSettingsCard(status: .requiresApproval, errorMessage: .loginPreviewLongError)
        .padding().frame(width: 340)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
#endif

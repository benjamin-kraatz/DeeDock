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
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { status.isEnabled }, set: setEnabled)) {
                    Text(.loginLaunchAtLogin)
                }
                .toggleStyle(.switch)
                .disabled(isPending || !status.canToggle)
                .accessibilityHint(Text(.loginToggleHint))

                Text(status.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let pendingOperation {
                    Text(pendingOperation.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                if status == .requiresApproval {
                    ViewThatFits(in: .horizontal) {
                        HStack { approvalActions }
                        VStack(alignment: .leading) { approvalActions }
                    }
                } else if status == .notFound || status == .unknown {
                    ViewThatFits(in: .horizontal) {
                        HStack { recoveryActions }
                        VStack(alignment: .leading) { recoveryActions }
                    }
                }
            }
            .padding(14)

            if let errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: dismissError) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.actionDismissError))
                    .help(Text(.actionDismissError))
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder private var approvalActions: some View {
        Button(.loginOpenSystemSettings, action: openSettings)
        Button(.loginCancelRequest, action: cancelRequest).disabled(isPending)
    }

    @ViewBuilder private var recoveryActions: some View {
        Button(.loginRefresh, action: refresh).disabled(isPending)
        Button(.loginOpenSystemSettings, action: openSettings)
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

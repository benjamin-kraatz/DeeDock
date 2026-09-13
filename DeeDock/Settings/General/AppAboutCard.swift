import SwiftUI

/// The top of the About & Updates page: the app's icon, name, and version, with an optional
/// trailing action such as checking for updates.
struct AppAboutCard<Accessory: View>: View {
    let version: String
    @ViewBuilder var accessory: Accessory

    /// The bundle's own name; macOS supplies it, so it is not translated.
    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ProcessInfo.processInfo.processName
    }

    var body: some View {
        SettingsCard {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: appName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(.updatesCurrentVersion)
                        Text(verbatim: version)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .layoutPriority(1)
                Spacer(minLength: SettingsMetrics.controlSpacing)
                accessory
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 14)
            .accessibilityElement(children: .contain)
        }
    }
}

extension AppAboutCard where Accessory == EmptyView {
    init(version: String) {
        self.init(version: version) { EmptyView() }
    }
}

#if DEBUG
#Preview("About card") {
    AppAboutCard(version: "0.9.2 (41)") { Button(.updatesCheck) {} }
        .padding(24)
        .frame(width: 640)
}
#endif

import SwiftUI

/// Settings › General › Privacy: the usage-data switches, what they cover, and what was sent.
///
/// Value-driven, so previews show every state without touching consent or a backend.
///
/// **NOTE**: the toggles are always returning true and are disabled on purpose during 0.x
struct AnalyticsSettingsCard: View {
    /// False when this build carries no API key; the switches are then shown but inert.
    var isConfigured = true
    var sharingEnabled: Bool
    var personProfilesEnabled: Bool
    /// Newest first.
    var recent: [AnalyticsRecord] = []
    var setSharingEnabled: (Bool) -> Void = { _ in }
    var setPersonProfilesEnabled: (Bool) -> Void = { _ in }
    var resetAnonymousID: () -> Void = {}
    /// Runs when the explanation comes on screen, which counts as the notice for a new user who
    /// left the tour before its privacy page.
    var noticeShown: () -> Void = {}

    @State private var didReset = false

    var body: some View {
        SettingsCard(title: .settingsPrivacy) {
            if !isConfigured {
                SettingsStatusRow(
                    symbol: "info.circle.fill",
                    tint: .secondary,
                    message: Text(.analyticsUnavailable)
                )
            }
            SettingsToggleRow(
                title: .analyticsShareTitle,
                subtitle: .analyticsShareSubtitle,
                isOn: Binding(get: { true }, set: setSharingEnabled),
                disabled: true
            )
            SettingsToggleRow(
                title: .analyticsProfileTitle,
                subtitle: .analyticsProfileSubtitle,
                isOn: Binding(
                    get: { true },
                    set: setPersonProfilesEnabled
                ),
                disabled: true
            )
            SettingsRow(
                title: .analyticsResetTitle,
                subtitle: didReset
                    ? .analyticsResetDone : .analyticsResetSubtitle
            ) {
                Button(.analyticsResetAction) {
                    resetAnonymousID()
                    didReset = true
                }
                .disabled(!sharingEnabled || !isConfigured)
            }
            VStack(alignment: .leading, spacing: 12) {
                AnalyticsDisclosureColumns()
                Text(.analyticsIntelligenceNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: AnalyticsDisclosure.documentationURL) {
                    Label {
                        Text(.analyticsLearnMore)
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .font(.callout)
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            AnalyticsRecentEventsView(records: recent)
        }
        .onAppear(perform: noticeShown)
    }
}

extension AnalyticsSettingsCard {
    /// The card bound to a live ``Analytics`` instance.
    init(analytics: Analytics) {
        self.init(
            isConfigured: analytics.isConfigured,
            sharingEnabled: analytics.consent.record.sharingEnabled,
            personProfilesEnabled: analytics.consent.record
                .personProfilesEnabled,
            recent: analytics.recent.records,
            setSharingEnabled: analytics.setSharingEnabled,
            setPersonProfilesEnabled: analytics.setPersonProfilesEnabled,
            resetAnonymousID: analytics.resetAnonymousID,
            noticeShown: analytics.noticeShown
        )
    }
}

#if DEBUG
    private enum AnalyticsSettingsPreview {
        static let records: [AnalyticsRecord] = [
            AnalyticsEvent.stackOpened(
                .downloads,
                presentation: .grid,
                sort: .recency,
                trigger: .click
            ).record,
            AnalyticsEvent.focusDockCommand(.windowSearch).record,
            AnalyticsEvent.peekOpened(
                .hover,
                cardCount: 3,
                totalWindowCount: 4,
                layout: .grid,
                style: .glass,
                size: .medium
            ).record,
        ]
    }

    #Preview("Privacy — sharing on, recent events") {
        ScrollView {
            AnalyticsSettingsCard(
                sharingEnabled: true,
                personProfilesEnabled: true,
                recent: AnalyticsSettingsPreview.records
            )
            .padding()
        }
        .frame(width: 600, height: 620)
    }

    #Preview("Privacy — sharing off, dark") {
        AnalyticsSettingsCard(
            sharingEnabled: false,
            personProfilesEnabled: true
        )
        .padding().frame(width: 600)
        .preferredColorScheme(.dark)
    }

    #Preview("Privacy — build without a key, narrow, large text") {
        ScrollView {
            AnalyticsSettingsCard(
                isConfigured: false,
                sharingEnabled: true,
                personProfilesEnabled: false
            )
            .padding()
        }
        .frame(width: 360, height: 700)
        .dynamicTypeSize(.accessibility2)
    }
#endif

import SwiftUI

/// The App Health settings: the collection and labelling switches, a paused-labelling row, the collector's status
/// with the stored data, Export and Delete, what is recorded, and the "Don't ask" list. Driven by plain values so
/// every state previews.
///
/// Rows that come and go (paused, error, the "Don't ask" card) settle in and out with the same arrival the Plugins
/// page uses; Reduce Motion fades them instead. Everything takes the page's tint.
struct AppHealthSettingsCardContent: View {
    let state: AppHealthSettingsState
    let actions: AppHealthSettingsActions
    /// Stands in for the environment in previews, which cannot write the accessibility keys on this SDK.
    var reduceMotionOverride: Bool?
    @State private var confirmingDelete = false
    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? environmentReduceMotion }

    /// A row settles 6 points down while it fades in and leaves the same way; Reduce Motion fades only.
    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
    }

    var body: some View {
        VStack(spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .appHealthTitle) {
                SettingsToggleRow(title: .appHealthCollect, subtitle: .appHealthCollectHelp,
                                  isOn: Binding(get: { state.collecting }, set: actions.setCollecting))
                SettingsToggleRow(title: .appHealthLabelling, subtitle: .appHealthLabellingHelp,
                                  isOn: Binding(get: { state.labelling }, set: actions.setLabelling),
                                  disabled: !state.collecting)
                if let pausedUntil = state.pausedUntil {
                    AppHealthPausedRow(until: pausedUntil, resume: actions.resumeLabelling)
                        .transition(arrival)
                }
                AppHealthDataStatusRow(phase: state.phase, summary: state.summary, activity: state.activity,
                                       reduceMotion: reduceMotion)
                if let error = state.error {
                    SettingsInlineError(message: error.message, dismiss: actions.dismissError)
                        .transition(arrival)
                }
                SettingsActionRow {
                    Button(.appHealthExport, action: actions.export)
                        .disabled(!state.summary.hasData || state.activity != .idle)
                    Button(role: .destructive) { confirmingDelete = true } label: { Text(.appHealthDelete) }
                        .disabled(!state.summary.hasData || state.activity != .idle)
                }
                AppHealthPrivacyNote(showsFinderLink: state.summary.hasData, revealInFinder: actions.revealInFinder)
            }
            .confirmationDialog(Text(.appHealthDeleteConfirm), isPresented: $confirmingDelete) {
                Button(role: .destructive, action: actions.deleteAll) { Text(.appHealthDelete) }
            } message: {
                Text(.appHealthDeleteHelp)
            }
            if !state.dontAsk.isEmpty {
                AppHealthDontAskCard(apps: state.dontAsk, allowAsking: actions.allowAsking, reduceMotion: reduceMotion)
                    .transition(arrival)
            }
        }
        .tint(SettingsPage.appHealth.tint)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.3), value: state.layout)
    }
}

extension AppHealthSettingsState {
    /// What decides which rows exist and what the status says. Changing it animates the card's layout; a text
    /// edit alone does not.
    struct Layout: Equatable {
        var collecting: Bool
        var phase: AppHealthController.Phase
        var paused: Bool
        var hasData: Bool
        var activity: AppHealthController.StorageActivity
        var error: AppHealthController.StorageError?
        var dontAsk: [String]
    }

    var layout: Layout {
        Layout(collecting: collecting, phase: phase, paused: pausedUntil != nil, hasData: summary.hasData,
               activity: activity, error: error, dontAsk: dontAsk.map(\.bundleID))
    }
}

extension AppHealthController.StorageError {
    var message: LocalizedStringResource {
        switch self {
        case .exportFailed: .appHealthExportFailed
        case .deleteFailed: .appHealthDeleteFailed
        }
    }
}

#if DEBUG
private enum AppHealthSettingsPreview {
    static let reference = Date(timeIntervalSince1970: 1_793_000_000)

    static func card(_ state: AppHealthSettingsState, reduceMotion: Bool? = nil) -> some View {
        ScrollView {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                AppHealthSettingsCardContent(state: state, actions: .inert, reduceMotionOverride: reduceMotion)
            }
            .padding(24)
        }
        .frame(width: SettingsMetrics.columnWidth, height: 720)
    }

    /// Deterministic names and symbols, so previews never ask Launch Services.
    static func display(_ bundleID: String, _ name: String) -> AppHealthAppDisplay {
        AppHealthAppDisplay(bundleID: bundleID, name: name,
                            icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil))
    }

    static let withData = AppHealthStorageSummary(bytes: 2_400_000, oldest: reference.addingTimeInterval(-3 * 86_400),
                                                  days: 4)
}

#Preview("Off") {
    AppHealthSettingsPreview.card(AppHealthSettingsState(collecting: false, labelling: false, summary: .empty))
}

#Preview("Collecting with data") {
    AppHealthSettingsPreview.card(AppHealthSettingsState(collecting: true, labelling: true, phase: .collecting,
                                                         summary: AppHealthSettingsPreview.withData))
}

#Preview("Paused, apps not asked about, dark") {
    AppHealthSettingsPreview.card(AppHealthSettingsState(
        collecting: true, labelling: true, phase: .collecting, summary: AppHealthSettingsPreview.withData,
        pausedUntil: AppHealthSettingsPreview.reference.addingTimeInterval(6 * 3600),
        dontAsk: [AppHealthSettingsPreview.display("com.example.Builder", "Builder"),
                  AppHealthSettingsPreview.display("com.example.Mail", "Mail")]))
        .preferredColorScheme(.dark)
}

#Preview("Sampling paused by sleep, German") {
    AppHealthSettingsPreview.card(AppHealthSettingsState(collecting: true, labelling: true, phase: .paused,
                                                         summary: AppHealthSettingsPreview.withData))
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Export failed, German") {
    AppHealthSettingsPreview.card(AppHealthSettingsState(collecting: false, labelling: true,
                                                         summary: AppHealthSettingsPreview.withData,
                                                         error: .exportFailed))
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Exporting, Reduce Motion") {
    AppHealthSettingsPreview.card(AppHealthSettingsState(collecting: true, labelling: false, phase: .collecting,
                                                         summary: AppHealthSettingsPreview.withData,
                                                         activity: .exporting), reduceMotion: true)
}
#endif

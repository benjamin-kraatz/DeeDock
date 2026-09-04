import SwiftUI

/// App-wide feature switches: the Shelf, the Trash tile, and Window Peek.
///
/// These are opt-in capabilities rather than appearance or placement choices, so they are
/// configured once for the whole app. Unlike the panes under Defaults, nothing here can be
/// overridden per display.
struct FeaturesSettingsPane: View {
    var focus: FocusSessionController? = nil
    var actions: ActionTilesController? = nil
    let store: DockSettingsStore
    let profiles: DisplayProfilesStore?
    let windowAccess: WindowAccessController?
    let screenCapture: ScreenCaptureAccessController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var source: SettingsValueSource {
        SettingsValueSource(store: store, profiles: profiles, context: nil)
    }
    private var locked: Bool { store.requiresReset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                if let focus { FocusSessionSettingsCard(controller: focus) }
                if let actions { ActionTilesSettingsCard(controller: actions) }
                SettingsCard(title: .settingsCapsules, footnote: .settingsCapsulesHelp) {
                    SettingsToggleRow(title: .settingsShowCapsules,
                                      isOn: source.binding(\.showSessionCapsules))
                }
                .disabled(locked)
                SettingsCard(title: .settingsShelf, footnote: .settingsShelfHelp) {
                    SettingsToggleRow(title: .settingsShowShelf, isOn: source.binding(\.showShelf))
                }
                .disabled(locked)
                SettingsCard(title: .settingsTrash, footnote: .settingsTrashHelp) {
                    SettingsToggleRow(title: .settingsShowTrash, isOn: source.binding(\.showTrash))
                    SettingsToggleRow(title: .settingsConfirmBeforeEmptyingTrash,
                                      isOn: source.binding(\.confirmBeforeEmptyingTrash))
                }
                .disabled(locked)
                if let windowAccess, let screenCapture {
                    // Permissions stay usable even when unreadable settings block persistent edits.
                    PreviewsSettingsPane(source: source, windowAccess: windowAccess,
                                         screenCapture: screenCapture,
                                         persistentSettingsDisabled: locked)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(paneBackground)
        .tint(SettingsSelection.featuresTint)
        .navigationTitle(Text(.settingsFeatures))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooterBar(errorMessage: store.errorMessage,
                              resetTitle: .settingsRestoreDefaults,
                              resetDisabled: false,
                              restoreDefaults: { store.restoreDefaults() })
        }
    }

    /// Matches the tinted wash every other pane draws behind its cards.
    private var paneBackground: some View {
        SettingsSelection.featuresTint
            .opacity(0.05)
            .mask {
                LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
    }
}

extension SettingsSelection {
    /// Identity color for Features, distinct from every category tint and from Modes.
    static let featuresTint = Color(red: 0.92, green: 0.28, blue: 0.55)
    static let featuresTileColors = [Color(red: 1.0, green: 0.47, blue: 0.72),
                                     Color(red: 0.83, green: 0.15, blue: 0.52)]
}

#if DEBUG
#Preview("Features") {
    FeaturesSettingsPane(store: DockSettingsStore(repository: DockSettingsRepository(
        defaults: UserDefaults(suiteName: "FeaturesPreview") ?? .standard)),
                         profiles: nil, windowAccess: nil, screenCapture: nil)
        .frame(width: 720, height: 560)
}
#endif

import SwiftUI

/// Scrolling content for the selected pane, tinted with that pane's identity color.
///
/// The sidebar already names the pane, so the content area carries no heading of its own.
/// Panes are keyed by category so switching cross-fades the whole stack instead of animating
/// unrelated controls into each other.
struct SettingsDetailView: View {
    let store: DockSettingsStore
    let category: SettingsCategory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        Binding(get: { store.value[keyPath: keyPath] }, set: { store.update(keyPath, to: $0) })
    }

    var body: some View {
        ScrollView {
            if let category {
                pane(for: category)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 22)
                    .id(category)
                    .transition(transition)
            } else {
                ContentUnavailableView {
                    Label {
                        Text(.settingsSelectCategory)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                .padding(.top, 80)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(paneWash)
        .tint(category?.tint ?? .accentColor)
        .disabled(store.requiresReset)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: category)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooterBar(errorMessage: store.errorMessage,
                              restoreDefaults: { store.restoreDefaults() })
        }
    }

    @ViewBuilder private func pane(for category: SettingsCategory) -> some View {
        switch category {
        case .appearance:
            AppearanceSettingsPane(iconSize: binding(\.iconSize),
                                   magnification: binding(\.magnification))
        case .position:
            PositionSettingsPane(reference: binding(\.positionReference),
                                 alignment: binding(\.alignment),
                                 horizontalOffset: binding(\.horizontalOffset),
                                 bottomDistance: binding(\.bottomDistance))
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .offset(y: 14).combined(with: .opacity), removal: .opacity)
    }

    /// A faint wash of the pane color ties the content area to the sidebar selection.
    private var paneWash: some View {
        LinearGradient(colors: [(category?.tint ?? .accentColor).opacity(0.12), .clear],
                       startPoint: .top, endPoint: .center)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: category)
            .ignoresSafeArea()
    }
}

import SwiftUI

/// Scrolling content for the selected pane, tinted with that pane's identity color.
///
/// The sidebar already names the pane, so the content area carries no heading of its own.
/// Panes are keyed by category so switching cross-fades the whole stack instead of animating
/// unrelated controls into each other.
struct SettingsDetailView: View {
    let store: DockSettingsStore
    let category: SettingsCategory?
    var context: SettingsOverrideContext? = nil
    var profileError: LocalizedStringResource? = nil
    var showZone: (() -> Void)?
    @Binding var displayCategory: SettingsCategory

    init(store: DockSettingsStore, category: SettingsCategory?, context: SettingsOverrideContext? = nil,
         profileError: LocalizedStringResource? = nil, showZone: (() -> Void)? = nil,
         displayCategory: Binding<SettingsCategory> = .constant(.appearance)) {
        self.store = store
        self.category = category
        self.context = context
        self.profileError = profileError
        self.showZone = showZone
        _displayCategory = displayCategory
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        SettingsValueSource(store: store, context: context).binding(keyPath)
    }

    var body: some View {
        ScrollView {
            if let category {
                VStack(alignment: .leading, spacing: 22) {
                    if let context { DisplaySettingsHeader(context: context, category: $displayCategory) }
                    pane(for: category)
                }
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
        .disabled(store.requiresReset || context?.profiles.requiresReset == true)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: category)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooterBar(errorMessage: profileError ?? store.errorMessage,
                              resetTitle: context == nil ? .settingsRestoreDefaults : .displayUseDefaults,
                              resetDisabled: context?.profiles.requiresReset == true,
                              restoreDefaults: {
                                  if let context { context.profiles.useDefaults(for: context.id) }
                                  else { store.restoreDefaults() }
                              })
        }
    }

    @ViewBuilder private func pane(for category: SettingsCategory) -> some View {
        switch category {
        case .behavior:
            BehaviorSettingsPane(source: SettingsValueSource(store: store, context: context), showZone: showZone)
        case .appearance:
            AppearanceSettingsPane(edge: SettingsValueSource(store: store, context: context).value.edge, iconSize: binding(\.iconSize),
                                   magnification: binding(\.magnification), itemSpacing: binding(\.itemSpacing),
                                   runningIndicatorStyle: binding(\.runningIndicatorStyle),
                                   animateIndicators: binding(\.animateIndicators),
                                   appearanceSettings: SettingsValueSource(store: store, context: context).value, overrideContext: context)
            DockTooltipSettingsPane(source: SettingsValueSource(store: store, context: context))
            DockFadingSettingsPane(source: SettingsValueSource(store: store, context: context))
        case .position:
            PositionSettingsPane(edge: binding(\.edge), reference: binding(\.positionReference),
                                 alignment: binding(\.alignment),
                                 alongEdgeOffset: binding(\.alongEdgeOffset),
                                 edgeDistance: binding(\.edgeDistance), overrideContext: context)
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

#if DEBUG
#Preview("Display overrides") {
    let profiles = DisplaySettingsPreview.make()
    SettingsDetailView(store: profiles.defaults, category: .appearance,
                       context: SettingsOverrideContext(profiles: profiles, id: "display.preview2"))
        .frame(width: 620, height: 650)
}
#Preview("Disconnected display") {
    let profiles = DisplaySettingsPreview.make()
    SettingsDetailView(store: profiles.defaults, category: .position,
                       context: SettingsOverrideContext(profiles: profiles, id: "display.preview3"),
                       displayCategory: .constant(.position))
        .frame(width: 620, height: 650)
}
#endif

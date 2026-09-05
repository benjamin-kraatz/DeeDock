import SwiftUI

/// Scrolling content for the selected pane, tinted with that pane's identity color.
///
/// The sidebar already names the pane, so the content area carries no heading of its own.
/// Panes are keyed by category so switching cross-fades the whole stack instead of animating
/// unrelated controls into each other.
struct SettingsDetailView: View {
    let store: DockSettingsStore
    let profiles: DisplayProfilesStore?
    let category: SettingsCategory?
    var context: SettingsOverrideContext? = nil
    var profileError: LocalizedStringResource? = nil
    var showZone: (() -> Void)?
    @Binding var displayCategory: SettingsCategory

    init(store: DockSettingsStore, profiles: DisplayProfilesStore? = nil,
         category: SettingsCategory?, context: SettingsOverrideContext? = nil,
         profileError: LocalizedStringResource? = nil, showZone: (() -> Void)? = nil,
         displayCategory: Binding<SettingsCategory> = .constant(.appearance)) {
        self.store = store
        self.profiles = profiles
        self.category = category
        self.context = context
        self.profileError = profileError
        self.showZone = showZone
        _displayCategory = displayCategory
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func binding<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        SettingsValueSource(store: store, profiles: profiles, context: context).binding(keyPath)
    }

    var body: some View {
        ScrollView {
            if let category {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                    if let context { DisplaySettingsHeader(context: context, category: $displayCategory) }
                    pane(for: category)
                        .disabled(settingsLocked)
                        .id(category)
                        .transition(transition)
                }
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
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
        .background(paneBackground)
        .tint(category?.tint ?? .accentColor)
        .navigationTitle(navigationTitle)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: category)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooterBar(errorMessage: profileError ?? store.errorMessage,
                              resetTitle: context == nil ? .settingsRestoreDefaults : .displayUseDefaults,
                              resetDisabled: context?.profiles.requiresReset == true,
                              restoreDefaults: {
                                  if let context { context.profiles.useDefaults(for: context.id) }
                                  else {
                                      store.restoreDefaults()
                                      profiles?.restoreDefaultVisibility()
                                  }
                              })
        }
    }

    /// Display panes are titled by the device; shared panes by the category the sidebar selected.
    private var navigationTitle: Text {
        if let context, let profile = context.profiles.document.profiles[context.id] {
            return Text(verbatim: profile.name)
        }
        return Text(category?.title ?? .settingsSelectCategory)
    }

    @ViewBuilder private func pane(for category: SettingsCategory) -> some View {
        switch category {
        case .behavior:
            BehaviorSettingsPane(source: SettingsValueSource(store: store, profiles: profiles, context: context), showZone: showZone)
        case .appearance:
            AppearanceSettingsPane(edge: SettingsValueSource(store: store, profiles: profiles, context: context).value.edge, iconSize: binding(\.iconSize),
                                   magnification: binding(\.magnification), itemSpacing: binding(\.itemSpacing),
                                   cornerRadius: binding(\.cornerRadius),
                                   runningIndicatorStyle: binding(\.runningIndicatorStyle),
                                   animateIndicators: binding(\.animateIndicators),
                                   appearanceSettings: SettingsValueSource(store: store, profiles: profiles, context: context).value, overrideContext: context)
            DockTooltipSettingsPane(source: SettingsValueSource(store: store, profiles: profiles, context: context))
            DockFadingSettingsPane(source: SettingsValueSource(store: store, profiles: profiles, context: context))
        case .position:
            PositionSettingsPane(edge: binding(\.edge), reference: binding(\.positionReference),
                                 alignment: binding(\.alignment),
                                 alongEdgeOffset: binding(\.alongEdgeOffset),
                                 edgeDistance: binding(\.edgeDistance), overrideContext: context)
        }
    }

    private var settingsLocked: Bool {
        store.requiresReset || context?.profiles.requiresReset == true
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .offset(y: 14).combined(with: .opacity), removal: .opacity)
    }

    /// The window's own material, with a whisper of the pane color at the top edge.
    ///
    /// macOS keeps content areas neutral, so the identity color stays a hint that fades out
    /// well before the first card instead of washing the whole pane.
    private var paneBackground: some View {
        (category?.tint ?? .accentColor)
            .opacity(0.05)
            .mask {
                LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
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

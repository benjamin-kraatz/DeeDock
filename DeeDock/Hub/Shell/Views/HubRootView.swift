import SwiftUI

/// The Hub's whole SwiftUI tree: glass, header, and the visible tab's content.
///
/// `query` and `prompt` belong to the visible tab's model; the coordinator passes bindings that
/// follow ``HubShellState/tab``. `content` builds one tab's view. Tab models are told about
/// visibility by the coordinator, not by this view's appearance, so a SwiftUI re-render never
/// starts or stops a tab's discovery.
///
/// `overlay` covers the header and the tab inside the glass, for a sheet-like card such as Lookout's
/// onboarding; it is empty otherwise.
struct HubRootView<Content: View, Overlay: View>: View {
    let state: HubShellState
    @Binding var query: String
    let prompt: LocalizedStringResource
    let actions: HubHeaderActions
    /// The visible tab's additions to the search field. With them, drags over the whole Hub are watched (never
    /// taken) so the field can open its drop well (`HubDragObserver`).
    var extras: (any HubSearchExtras)?
    @ViewBuilder let content: (HubTab) -> Content
    @ViewBuilder var overlay: () -> Overlay

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HubGlassContainer(state: state) {
            VStack(spacing: 0) {
                HubHeaderView(state: state, query: $query, prompt: prompt, actions: actions, extras: extras)
                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.075))
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
                HubTabContent(state: state, content: content)
            }
            .modifier(HubDragObservation(extras: extras))
            .overlay { overlay() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

/// The visible tab's content. A switch cross-fades and slides the new content 18 points in from
/// the side it was selected toward, as the mockup does; the old content leaves at once. Reduce
/// Motion keeps only the fade.
struct HubTabContent<Content: View>: View {
    let state: HubShellState
    @ViewBuilder let content: (HubTab) -> Content

    var body: some View {
        let offset = state.reduceMotion ? 0 : HubStyle.tabContentOffset * state.switchDirection
        ZStack {
            content(state.tab)
                .id(state.tab)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: offset)),
                    removal: .identity))
        }
        .animation(state.reduceMotion ? .easeOut(duration: 0.15) : HubStyle.tabContent, value: state.tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

extension HubRootView where Overlay == EmptyView {
    /// A Hub with nothing over its content.
    init(state: HubShellState, query: Binding<String>, prompt: LocalizedStringResource, actions: HubHeaderActions,
         @ViewBuilder content: @escaping (HubTab) -> Content) {
        self.init(state: state, query: query, prompt: prompt, actions: actions, extras: nil, content: content) {
            EmptyView()
        }
    }
}

/// Watches drags over the Hub for a tab with search extras; without them it registers no types, so the Hub isn't a
/// drop target at all.
///
/// The drop modifier stays attached for every tab. Adding it only when there are extras would give the whole Hub a
/// different identity whenever Files (the one tab with extras) comes or goes, and SwiftUI would rebuild the header
/// and tab content mid-switch, drawing the old and new trees on top of each other.
private struct HubDragObservation: ViewModifier {
    let extras: (any HubSearchExtras)?

    func body(content: Content) -> some View {
        content.onDrop(of: extras?.searchDropTypes ?? [], delegate: HubDragObserver(extras: extras))
    }
}

// MARK: - Previews

/// Stand-in tab content for previews: no models, no workspace access.
private struct HubPreviewTabStub: View {
    let tab: HubTab

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tab.symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(tab.title)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HubRootPreview: View {
    let state: HubShellState
    @State private var query = ""

    var body: some View {
        HubRootView(state: state, query: $query, prompt: state.tab.title,
                    actions: HubHeaderActions(select: { state.select($0) }, togglePin: {}, close: {})) { tab in
            HubPreviewTabStub(tab: tab)
        }
        .padding(state.isDetached ? 0 : 28)
        .frame(width: 1240, height: 700)
        .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

#Preview("Anchored, dark") {
    HubRootPreview(state: .preview(tab: .apps))
        .preferredColorScheme(.dark)
}

#Preview("Anchored, light") {
    HubRootPreview(state: .preview(tab: .files))
        .preferredColorScheme(.light)
}

#Preview("Detached") {
    HubRootPreview(state: .preview(tab: .windows, detached: true))
}

#Preview("Reduce Transparency") {
    HubRootPreview(state: .preview(tab: .apps, reduceTransparency: true))
}

#Preview("German") {
    HubRootPreview(state: .preview(tab: .windows))
        .environment(\.locale, Locale(identifier: "de"))
}

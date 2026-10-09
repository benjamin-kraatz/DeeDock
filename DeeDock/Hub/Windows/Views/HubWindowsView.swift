import SwiftUI

/// The Hub's Windows tab: a summary line with Open Radar, permission hints when needed, and
/// wrapping app group cards of window cards.
struct HubWindowsView: View {
    /// Coordinate space the cards report their frames in, for up/down arrow navigation.
    static let gridSpace = "HubWindowsGrid"

    let model: HubWindowsModel

    init(model: HubWindowsModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            HubWindowsSummaryBar(windowCount: model.windowCount, appCount: model.appCount, openRadar: model.openRadar)
            if !model.access.windows || !model.access.thumbnails {
                HubWindowsPermissionHint(access: model.access,
                                         openAccessibilitySettings: model.openAccessibilitySettings,
                                         openScreenRecordingSettings: model.openScreenRecordingSettings)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(model.reduceMotion ? nil : HubStyle.motion, value: model.access)
    }

    @ViewBuilder
    private var content: some View {
        if model.shownGroups.isEmpty {
            switch model.phase {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .loaded:
                HubWindowsEmptyState(isFiltering: !model.query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            HubWindowsGrid(model: model)
        }
    }
}

/// The scrolling, wrapping grid of app group cards. Keeps the keyboard selection in view.
private struct HubWindowsGrid: View {
    let model: HubWindowsModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HubWindowsWrapLayout(spacing: 14, lineSpacing: 14) {
                    ForEach(Array(model.shownGroups.enumerated()), id: \.element.id) { index, group in
                        HubWindowGroupCard(group: group, icon: model.icons[group.id], thumbnails: model.thumbnails,
                                           selection: model.selection, reduceMotion: model.reduceMotion,
                                           activate: model.activate,
                                           reportFrame: { id, frame in model.cardFrames[id] = frame })
                            .modifier(HubWindowsStaggeredAppear(index: index, reduceMotion: model.reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .coordinateSpace(.named(HubWindowsView.gridSpace))
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                if model.reduceMotion {
                    proxy.scrollTo(selection)
                } else {
                    withAnimation(HubStyle.motion) { proxy.scrollTo(selection) }
                }
            }
        }
    }
}

/// Group cards rise and fade in one after another (40 ms apart, like the mockup's `.stag`);
/// under Reduce Motion they are simply there.
private struct HubWindowsStaggeredAppear: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.96)
            .offset(y: visible ? 0 : 10)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(min(index, 12)) * 0.04)) {
                    shown = true
                }
            }
    }
}

/// Shown when there are no windows at all, or none match the search.
struct HubWindowsEmptyState: View {
    let isFiltering: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isFiltering ? "magnifyingglass" : "macwindow.on.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(isFiltering ? .hubWindowsNoResults : .hubWindowsEmpty)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

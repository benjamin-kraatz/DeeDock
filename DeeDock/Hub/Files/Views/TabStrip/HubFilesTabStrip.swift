import SwiftUI

/// The 40 pt strip of browser tabs with a New Tab button. The selected tab's fill and accent
/// underline are one shared shape that slides to the newly selected tab.
struct HubFilesTabStrip: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme
    @Namespace private var selectedTab

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(model.tabs) { tab in
                        HubFilesTabItem(model: model, tab: tab, selectedTab: selectedTab)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.95, anchor: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))))
                    }
                }
            }
            .scrollIndicators(.never)
            .fixedSize(horizontal: false, vertical: true)
            HubFilesNewTabButton { model.newTab() }
                .padding(.bottom, 3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: HubFilesMetrics.tabStripHeight, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(height: 0.5)
        }
        .animation(HubFilesMotion.animation(.spring(response: 0.35, dampingFraction: 0.75)), value: model.tabs.map(\.id))
        .animation(HubFilesMotion.layout, value: model.selectedTabID)
    }
}

/// The + button that opens a tab (⌘T).
private struct HubFilesNewTabButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .background(hovered ? HubFilesTheme(scheme).chip : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.88))
        .onHover { hovered = $0 }
        .help(Text(.hubFilesNewTabHelp))
        .accessibilityLabel(Text(.hubFilesNewTab))
    }
}

#Preview("Tab strip") {
    HubFilesTabStrip(model: .preview())
        .frame(width: 700)
        .environment(\.hubFilesIconSource, .typeOnly)
}

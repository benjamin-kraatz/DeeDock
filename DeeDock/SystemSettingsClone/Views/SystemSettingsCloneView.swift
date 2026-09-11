import SwiftUI

/// Searchable springboard that only deep-links into macOS System Settings.
///
/// Two modes share one window. Browsing shows the whole catalog as a scrolling canvas
/// with a sidebar that follows it. Typing swaps the canvas for ranked results that
/// ↑/↓ and Return drive without leaving the search field.
struct SystemSettingsCloneView: View {
    var openPane: (SystemSettingsClonePane) -> SystemSettingsDeepLinkOpenResult = {
        SystemSettingsDeepLinkOpener.open($0)
    }
    var openRoot: () -> SystemSettingsDeepLinkOpenResult = {
        SystemSettingsDeepLinkOpener.openRoot()
    }

    @AppStorage(SystemSettingsCloneRecents.storageKey) private var recentPaneIDs = ""
    @State private var searchIndex = SystemSettingsCloneSearchIndex()
    @State private var searchText = ""
    @State private var selectedResult = 0
    @State private var focusRequest = 0
    /// Topmost section on the canvas, bound to its scroll position.
    @State private var scrolledSection: SystemSettingsCloneSection? = .quickAccess
    /// Section the sidebar highlights. Lags `scrolledSection` briefly after a click so the
    /// highlight does not bounce back when the last sections cannot reach the top.
    @State private var highlightedSection: SystemSettingsCloneSection = .quickAccess
    @State private var jumpLockUntil = Date.distantPast
    /// Frozen while the window is in use so tiles never move under the pointer.
    @State private var quickAccess: [SystemSettingsClonePane] = []
    @State private var launchCounts: [String: Int] = [:]
    @State private var toast: SystemSettingsCloneToast?
    @State private var toastTask: Task<Void, Never>?
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }
    private var results: [SystemSettingsCloneSearchResult] { searchIndex.search(query) }
    private var motion: Animation? { .systemSettingsClone(reduceMotion: reduceMotion) }

    var body: some View {
        HStack(spacing: 0) {
            SystemSettingsCloneSidebar(
                highlighted: highlightedSection,
                isSearching: isSearching,
                jump: jumpFromSidebar,
                openRoot: { present(openRoot(), for: nil) }
            )
            .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // An inset rather than a stacked row: the scroll views keep running under the
                // floating search capsule, so content shows through its glass as it scrolls.
                .safeAreaInset(edge: .top, spacing: 0) {
                    SystemSettingsCloneSearchField(text: $searchText, focusRequest: focusRequest, onCommand: handle)
                        .frame(maxWidth: SystemSettingsCloneMetrics.contentMaxWidth - 120)
                        .padding(.horizontal, 28)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                }
        }
        // Content runs under the hidden titlebar; the sidebar reserves room for the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
        .background { SystemSettingsCloneAmbience(tint: isSearching ? results.first?.pane.tint : highlightedSection.ambientTint) }
        .overlay(alignment: .bottom) { toastOverlay }
        .background { keyboardShortcuts }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            quickAccess = SystemSettingsCloneRecents.quickAccess(from: recentPaneIDs)
            focusRequest += 1
        }
        .onChange(of: appearsActive) { _, active in
            // Refresh recents only when the person comes back, never mid-click.
            guard active else { return }
            withAnimation(motion) { quickAccess = SystemSettingsCloneRecents.quickAccess(from: recentPaneIDs) }
        }
        .onChange(of: query) { _, _ in selectedResult = 0 }
        .onChange(of: scrolledSection) { _, section in
            guard let section, Date.now >= jumpLockUntil else { return }
            highlightedSection = section
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if !isSearching {
                SystemSettingsCloneCanvas(
                    quickAccess: quickAccess,
                    scrolledSection: $scrolledSection,
                    launchCounts: launchCounts,
                    open: open
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            } else if results.isEmpty {
                SystemSettingsCloneEmptyState(query: query) { searchText = "" }
                    .transition(.opacity)
            } else {
                SystemSettingsCloneSearchResults(
                    results: results,
                    selectedIndex: $selectedResult,
                    launchCounts: launchCounts,
                    open: open
                )
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .animation(motion, value: isSearching)
        .animation(motion, value: results.isEmpty)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            SystemSettingsCloneToastView(toast: toast) { dismissToast() }
                .padding(.bottom, 18)
                .padding(.leading, SystemSettingsCloneMetrics.sidebarWidth + 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast)
        }
    }

    /// Invisible buttons that own window-level shortcuts: ⌘F focuses search, ⌘1–⌘9 jump to a category.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { focusRequest += 1 }
                .keyboardShortcut("f", modifiers: .command)
            ForEach(Array(SystemSettingsDeepLinkCatalog.categories.prefix(9).enumerated()), id: \.element.id) { index, category in
                Button("") {
                    searchText = ""
                    jump(to: .category(category.id))
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func handle(_ command: SystemSettingsCloneSearchCommand) {
        switch command {
        case .moveDown:
            guard isSearching, !results.isEmpty else { return }
            selectedResult = min(selectedResult + 1, results.count - 1)
        case .moveUp:
            guard isSearching else { return }
            selectedResult = max(selectedResult - 1, 0)
        case .submit:
            let current = results
            guard current.indices.contains(selectedResult) else { return }
            open(current[selectedResult].pane)
        case .cancel:
            searchText = ""
        }
    }

    private func jumpFromSidebar(_ section: SystemSettingsCloneSection) {
        searchText = ""
        jump(to: section)
    }

    private func jump(to section: SystemSettingsCloneSection) {
        highlightedSection = section
        jumpLockUntil = .now.addingTimeInterval(0.9)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.1)) {
            scrolledSection = section
        }
    }

    private func open(_ pane: SystemSettingsClonePane) {
        launchCounts[pane.id, default: 0] += 1
        recentPaneIDs = SystemSettingsCloneRecents.recording(pane.id, in: recentPaneIDs)
        present(openPane(pane), for: pane)
    }

    private func present(_ result: SystemSettingsDeepLinkOpenResult, for pane: SystemSettingsClonePane?) {
        switch result {
        case .opened:
            if let pane { show(.opening(pane)) } else { dismissToast() }
        case .openedRoot:
            // Opening the root on purpose is not a fallback worth warning about.
            if pane == nil { dismissToast() } else { show(.openedRoot) }
        case .failed:
            show(.failed)
        }
    }

    private func show(_ newToast: SystemSettingsCloneToast) {
        toastTask?.cancel()
        withAnimation(motion) { toast = newToast }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: newToast.lifetime)
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        withAnimation(motion) { toast = nil }
    }
}

/// Soft color field behind the content that takes the hue of the current section.
private struct SystemSettingsCloneAmbience: View {
    let tint: SystemSettingsCloneTint?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let color = (tint ?? .gray).accent
            Ellipse()
                .fill(color.opacity(colorScheme == .dark ? 0.22 : 0.14))
                .frame(width: proxy.size.width * 0.9, height: proxy.size.height * 0.55)
                .offset(x: proxy.size.width * 0.3, y: -proxy.size.height * 0.28)
                .blur(radius: 90)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: tint)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Springboard") {
    SystemSettingsCloneView(openPane: { _ in .opened }, openRoot: { .openedRoot })
        .frame(width: 1040, height: 760)
}

#Preview("German") {
    SystemSettingsCloneView(openPane: { _ in .opened }, openRoot: { .openedRoot })
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 1040, height: 760)
}

#Preview("Dark, fallback toast") {
    SystemSettingsCloneView(openPane: { _ in .openedRoot }, openRoot: { .openedRoot })
        .preferredColorScheme(.dark)
        .frame(width: 1040, height: 760)
}
#endif

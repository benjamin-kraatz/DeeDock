import SwiftUI

/// The badge history window: what an app's badge is doing now, and what it did during a session.
///
/// Native tabs, list selection and buttons provide keyboard and VoiceOver navigation. Nothing here
/// samples badges or changes an app; the store is read, and every write is an explicit control.
struct BadgeMemoryView: View {
    let memory: BadgeMemoryStore
    @Bindable var presentation: BadgeMemoryPresentation
    let activate: (String) -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmsClear = false

    /// A selected app stays listed even after its history was deleted, so the pane does not vanish
    /// underneath the selection.
    private var paths: [String] {
        Set(memory.document.apps.keys).union(presentation.path.map { [$0] } ?? []).sorted()
    }

    /// The selected app's own color carries the window. Nothing selected keeps the system accent.
    private var tint: Color {
        guard presentation.tab == 0, let path = presentation.path else { return .accentColor }
        return BadgeAppArtwork.tint(path, dark: colorScheme == .dark) ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $presentation.tab) {
                Tab(String(localized: .badgeMemoryDetails), systemImage: "app.badge", value: 0) {
                    details
                }
                Tab(String(localized: .badgeMemoryDigest), systemImage: "timer", value: 1) {
                    BadgeDigestView(memory: memory, activate: activate)
                }
            }
            .overlay(alignment: .top) { wash }
            .overlay(alignment: .top) { banners }
            Divider()
            BadgeMemoryFooter(memory: memory, clearAll: { confirmsClear = true }, close: close)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(.badgeMemoryClearAll, isPresented: $confirmsClear) {
            Button(.badgeMemoryClearAll, role: .destructive) { memory.clearAll() }
        } message: { Text(.badgeMemoryClearHelp) }
    }

    @ViewBuilder private var details: some View {
        if paths.isEmpty {
            ContentUnavailableView {
                Label(.badgeMemoryDetails, systemImage: "app.badge")
            } description: {
                Text(.badgeMemoryEmpty)
            }
        } else {
            HStack(spacing: 0) {
                BadgeAppList(paths: paths, memory: memory, selection: $presentation.path)
                    .frame(width: 232)
                Divider()
                Group {
                    if let path = presentation.path {
                        BadgeDetailsView(memory: memory, path: path, activate: { activate(path) })
                    } else {
                        ContentUnavailableView {
                            Label(.badgeMemorySelectApp, systemImage: "sidebar.left")
                        } description: {
                            Text(.badgeMemoryNoAppSelected)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Storage and activation problems belong above whichever tab is open: both outlive a tab
    /// switch, and neither is caused by the tab the user is looking at.
    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if memory.storageFailed {
                BadgeMemoryBanner(message: .badgeMemoryStorageFailed, symbol: "externaldrive.badge.xmark")
            }
            if presentation.activationFailed {
                BadgeMemoryBanner(message: .badgeMemoryActivationFailed, symbol: "exclamationmark.triangle.fill")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    /// A wash in the selected app's color, so the window is recognizably about that app.
    private var wash: some View {
        LinearGradient(colors: [tint.opacity(reduceTransparency ? 0 : 0.14), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 130)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A problem the user can act on, stated once, in the same shape as the Shelf's banners.
private struct BadgeMemoryBanner: View {
    let message: LocalizedStringResource
    let symbol: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }
}

/// Collection is a preference, not an action, so it stays visible next to the limits it obeys.
private struct BadgeMemoryFooter: View {
    let memory: BadgeMemoryStore
    let clearAll: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { memory.document.collectFocus }, set: memory.setCollectFocus)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(.badgeMemoryCollect)
                    Text(.badgeMemoryRetention)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .disabled(memory.requiresReset)
            HStack {
                Button(.badgeMemoryClearAll, role: .destructive, action: clearAll)
                Spacer(minLength: 12)
                Button(.badgeMemoryClose, action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

#if DEBUG
@MainActor private func badgeMemoryPreview(tab: Int, path: String?) -> some View {
    let presentation = BadgeMemoryPresentation()
    presentation.tab = tab
    presentation.path = path
    return BadgeMemoryView(memory: BadgeMemoryStore(defaults: UserDefaults(suiteName: "BadgeWindowPreview")!),
                           presentation: presentation, activate: { _ in }, close: {})
}

#Preview("Details, nothing tracked") {
    badgeMemoryPreview(tab: 0, path: nil).frame(width: 780, height: 620)
}

#Preview("Details, one app selected") {
    badgeMemoryPreview(tab: 0, path: "/Applications/Mail.app").frame(width: 780, height: 620)
}

#Preview("Focus digest, German") {
    badgeMemoryPreview(tab: 1, path: nil)
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 780, height: 620)
}
#endif

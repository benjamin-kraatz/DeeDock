import SwiftUI

/// Searchable guide that only deep-links into macOS System Settings.
struct SystemSettingsCloneView: View {
    var openPane: (SystemSettingsClonePane) -> SystemSettingsDeepLinkOpenResult = {
        SystemSettingsDeepLinkOpener.open($0)
    }
    var openRoot: () -> SystemSettingsDeepLinkOpenResult = {
        SystemSettingsDeepLinkOpener.openRoot()
    }

    @State private var selection: SystemSettingsCloneCategory.ID? = .meAndPrivacy
    @State private var searchText = ""
    @State private var notice: SystemSettingsCloneNotice?

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }

    private var visibleGroups: [SystemSettingsCloneCategory] {
        if isSearching {
            return SystemSettingsDeepLinkCatalog.categories.compactMap { category in
                let panes = category.panesMatching(query)
                guard !panes.isEmpty else { return nil }
                return SystemSettingsCloneCategory(
                    id: category.id,
                    title: category.title,
                    summary: category.summary,
                    symbolName: category.symbolName,
                    panes: panes
                )
            }
        }
        guard let selection, let category = SystemSettingsDeepLinkCatalog.category(id: selection) else {
            return []
        }
        return [category]
    }

    var body: some View {
        NavigationSplitView {
            SystemSettingsCloneSidebar(
                selection: $selection,
                query: query,
                openRoot: { handle(openRoot()) }
            )
            .navigationSplitViewColumnWidth(min: 210, ideal: SystemSettingsCloneMetrics.sidebarIdeal, max: 300)
        } detail: {
            detail
                .navigationTitle(Text(.systemSettingsCloneTitle))
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text(.systemSettingsCloneSearchPrompt))
        .frame(minWidth: 760, minHeight: 540)
    }

    @ViewBuilder
    private var detail: some View {
        if visibleGroups.isEmpty {
            SystemSettingsCloneEmptyState(query: query) {
                searchText = ""
            }
        } else {
            SystemSettingsCloneCategoryDetail(groups: visibleGroups, open: { handle(openPane($0)) })
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let notice {
                SystemSettingsCloneNoticeBanner(notice: notice) {
                    self.notice = nil
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(SystemSettingsClonePalette.copper)
                    .accessibilityHidden(true)
                Text(.systemSettingsCloneFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private func handle(_ result: SystemSettingsDeepLinkOpenResult) {
        switch result {
        case .opened:
            notice = nil
        case .openedRoot:
            notice = .openedRoot
        case .failed:
            notice = .failed
        }
    }
}

/// Non-blocking result of a deep-link attempt.
enum SystemSettingsCloneNotice: Equatable {
    case openedRoot
    case failed

    var message: LocalizedStringResource {
        switch self {
        case .openedRoot: .systemSettingsCloneOpenedRoot
        case .failed: .systemSettingsCloneOpenFailed
        }
    }
}

/// Dismissible banner for a fallback or failed open.
struct SystemSettingsCloneNoticeBanner: View {
    let notice: SystemSettingsCloneNotice
    var dismiss: () -> Void

    private var isFailure: Bool { notice == .failed }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isFailure ? .orange : SystemSettingsClonePalette.copper)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(.actionDismissError))
                .help(Text(.actionDismissError))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            (isFailure ? Color.orange : SystemSettingsClonePalette.copper).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Clone window") {
    SystemSettingsCloneView(openPane: { _ in .opened }, openRoot: { .openedRoot })
        .frame(width: 920, height: 700)
}

#Preview("German") {
    SystemSettingsCloneView(openPane: { _ in .opened }, openRoot: { .openedRoot })
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 920, height: 700)
}

#Preview("Dark") {
    SystemSettingsCloneView(openPane: { _ in .opened }, openRoot: { .openedRoot })
        .preferredColorScheme(.dark)
        .frame(width: 920, height: 700)
}
#endif

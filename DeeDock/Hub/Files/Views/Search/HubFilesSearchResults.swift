import SwiftUI

/// Search results replacing the panes while the header field has a query, in the mockup's Sections layout
/// (`docs/mockups/lookout.html`): a scope bar with Lookout's status chip, then "Names · Spotlight" with the name
/// rows, then "Lookout · by content" (`LookoutSection`).
///
/// Every row is a direct child of one `LazyVStack`, so the arrow keys' scroll requests reach rows in either section
/// (`HubFilesSearchResultID`). Spotlight's rows show as soon as they arrive; Lookout fills in beneath them.
struct HubFilesSearchResults: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HubFilesSearchScopeBar(model: model)
            Rectangle().fill(HubFilesTheme(scheme).line).frame(height: 0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HubFilesNameResultsSection(model: model)
                        if model.showsLookoutSection {
                            LookoutSection(model: model)
                        }
                    }
                    .padding(EdgeInsets(top: 2, leading: 10, bottom: 14, trailing: 10))
                    .animation(HubFilesMotion.layout, value: model.visibleLookoutHits.map(\.id))
                }
                .onChange(of: model.searchScrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(HubFilesMotion.quick) { proxy.scrollTo(request.id) }
                }
            }
        }
    }
}

/// "Names · Spotlight · N" and the name rows, or a spinner while Spotlight looks and "No file or folder names contain
/// this." when it found none. Sibling views, so each row is its own lazy child of the results' stack.
private struct HubFilesNameResultsSection: View {
    let model: HubFilesModel

    var body: some View {
        let results = model.searchResults
        let searching = model.search.isSearching && model.previewOverrides.searchResults == nil
        HubFilesSearchSectionHeader(section: .names, count: searching && results.isEmpty ? nil : results.count)
        if results.isEmpty {
            Group {
                if searching {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                } else {
                    Text(.lookoutNamesEmpty)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(results) { item in
            HubFilesSearchRow(model: model, item: item)
                .id(HubFilesSearchResultID.name(item.url))
        }
    }
}

/// "Search: This Mac | “Folder”", and Lookout's status chip at the trailing end.
private struct HubFilesSearchScopeBar: View {
    let model: HubFilesModel

    var body: some View {
        HStack(spacing: 8) {
            Text(.hubFilesSearchIn)
            HubFilesScopeButton(title: String(localized: .hubFilesSearchThisMac), isOn: model.searchScope == .thisMac) {
                model.searchScope = .thisMac
            }
            HubFilesScopeButton(title: "“\(model.displayName(for: model.searchFolder))”",
                                isOn: model.searchScope == .currentFolder) {
                model.searchScope = .currentFolder
            }
            Spacer(minLength: 8)
            // Always shown, "Lookout off" included, as in the mockup: it's the way to Lookout's settings.
            LookoutStatusChip(status: model.lookoutStatus, downloadProgress: model.lookoutDownloadProgress,
                              onSetUpLookout: { model.onSetUpLookout() },
                              onOpenLookoutSettings: { model.onOpenLookoutSettings() })
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 42)
    }
}

/// One scope choice.
private struct HubFilesScopeButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = HubFilesTheme(scheme)
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? theme.accentSelection : theme.chip, in: .rect(cornerRadius: 8))
                .overlay {
                    if isOn { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accentLine, lineWidth: 0.5) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(HubFilesMotion.quick, value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

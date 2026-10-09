import SwiftUI

/// Search results replacing the panes while the header field has a query: a scope bar, a
/// Name / Where / Date Modified / Size header, and rows with the match highlighted.
struct HubFilesSearchResults: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let results = model.searchResults
        VStack(spacing: 0) {
            HubFilesSearchScopeBar(model: model, resultCount: results.count)
            HubFilesSearchHeader()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            HubFilesSearchRow(model: model, item: item)
                                .id(item.url)
                        }
                    }
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10))
                }
                .overlay {
                    if results.isEmpty {
                        Group {
                            if model.search.isSearching && model.previewOverrides.searchResults == nil {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(.hubFilesNoResults)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .onChange(of: model.searchScrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(HubFilesMotion.quick) { proxy.scrollTo(request.url) }
                }
            }
        }
    }
}

/// "Search: This Mac | “Folder”" and the result count.
private struct HubFilesSearchScopeBar: View {
    let model: HubFilesModel
    let resultCount: Int

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
            Text(.hubFilesResultCount(resultCount))
                .monospacedDigit()
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

/// The results' column titles.
private struct HubFilesSearchHeader: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            Text(.hubFilesColumnName).frame(maxWidth: .infinity, alignment: .leading)
            Text(.hubFilesColumnWhere).frame(width: HubFilesMetrics.whereColumnWidth, alignment: .leading)
            Text(.hubFilesColumnModified).frame(width: HubFilesMetrics.modifiedColumnWidth, alignment: .leading)
            Text(.hubFilesColumnSize).frame(width: HubFilesMetrics.sizeColumnWidth, alignment: .trailing)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: HubFilesMetrics.listHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(height: 0.5)
        }
        .padding(.horizontal, 10)
    }
}

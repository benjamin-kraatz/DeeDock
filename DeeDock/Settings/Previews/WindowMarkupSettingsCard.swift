import SwiftUI
import UniformTypeIdentifiers

/// Markup preferences: the saved file's format, the search engine, and the folder markups go to.
///
/// The folder is where **Send to Shelf** writes and where the save panel starts. Nothing else
/// writes there, and choosing a folder never moves files already in it.
struct WindowMarkupSettingsCard: View {
    let source: SettingsValueSource
    let disabled: Bool
    @State private var choosingFolder = false

    private var settings: DockSettings { source.value }
    private var folder: URL { WindowMarkupFolder.url(configured: settings.windowMarkupFolder) }

    var body: some View {
        SettingsCard(title: .markupSettingsTitle, footnote: .markupSettingsHelp) {
            SettingsPickerRow(title: .markupSettingsFormat, options: WindowMarkupFormat.settingsOptions,
                              selection: source.binding(\.windowMarkupFormat))
            SettingsPickerRow(title: .markupSettingsSearchEngine, options: WindowMarkupSearchEngine.settingsOptions,
                              selection: source.binding(\.windowMarkupSearchEngine))
            SettingsStackedRow(title: .markupSettingsFolder, subtitle: .markupSettingsFolderHelp) {
                HStack(spacing: 11) {
                    SettingsIconTile(glyph: .symbol("folder.fill"), colors: SettingsPage.windowPeek.tileColors, size: 24)
                    Text(verbatim: folder.path)
                        .font(.callout)
                        .lineLimit(1).truncationMode(.middle)
                        .help(Text(verbatim: folder.path))
                    Spacer(minLength: SettingsMetrics.controlSpacing)
                    Button(.markupSettingsChooseFolder) { choosingFolder = true }
                    Button(.markupSettingsResetFolder) { source.binding(\.windowMarkupFolder).wrappedValue = nil }
                        .disabled(settings.windowMarkupFolder == nil)
                }
            }
        }
        .disabled(disabled)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            source.binding(\.windowMarkupFolder).wrappedValue = url.path
        }
    }
}

private extension WindowMarkupFormat {
    static var settingsOptions: [SettingsOption<Self>] {
        [.init(value: .png, title: .markupFormatPNG, symbol: "photo"),
         .init(value: .jpeg, title: .markupFormatJPEG, symbol: "photo")]
    }
}

private extension WindowMarkupSearchEngine {
    static var settingsOptions: [SettingsOption<Self>] {
        allCases.map { .init(value: $0, title: $0.title, symbol: "magnifyingglass") }
    }
}

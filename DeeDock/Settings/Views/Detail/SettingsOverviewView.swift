import SwiftUI

/// A section's landing screen: what it is, then the pages it holds.
///
/// Pages the build or the machine cannot offer are dropped instead of shown disabled, and a group
/// that empties out takes its card with it, so the overview never lists a dead end.
struct SettingsOverviewView<Header: View>: View {
    let section: SettingsSection
    let title: Text
    var isAvailable: (SettingsPage) -> Bool = { _ in true }
    /// Short trailing state for a row, such as On or Off, so a person can scan without opening pages.
    var status: (SettingsPage) -> LocalizedStringResource? = { _ in nil }
    let open: (SettingsPage) -> Void
    /// Section-specific controls shown between the heading and the page list.
    @ViewBuilder var header: Header

    private var groups: [[SettingsPage]] {
        section.pageGroups.map { $0.filter(isAvailable) }.filter { !$0.isEmpty }
    }

    var body: some View {
        SettingsPageScaffold {
            header
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                SettingsLinkCard(pages: group, status: status, open: open)
            }
        }
        .navigationTitle(title)
    }
}

extension SettingsOverviewView where Header == EmptyView {
    /// Fixed sections take their title from the section itself.
    init(section: SettingsSection, isAvailable: @escaping (SettingsPage) -> Bool = { _ in true },
         status: @escaping (SettingsPage) -> LocalizedStringResource? = { _ in nil },
         open: @escaping (SettingsPage) -> Void) {
        let title = Text(section.title ?? .settingsGeneral)
        self.init(section: section, title: title, isAvailable: isAvailable, status: status, open: open) {
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Dock overview") {
    SettingsOverviewView(section: .dock, open: { _ in })
        .frame(width: 720, height: 640)
}
#Preview("Dock Extras overview — dark") {
    SettingsOverviewView(section: .extras,
                         isAvailable: { $0 != .actionTiles },
                         status: { [.capsules, .badges].contains($0) ? .settingsStatusOn : .settingsStatusOff },
                         open: { _ in })
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 640)
}
#Preview("Deprecated overview") {
    SettingsOverviewView(section: .deprecated, open: { _ in })
        .frame(width: 720, height: 640)
}
#endif

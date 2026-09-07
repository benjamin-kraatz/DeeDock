import SwiftUI

/// A section's landing screen: what it is, then the pages it holds.
///
/// Pages the build or the machine cannot offer are dropped instead of shown disabled, and a group
/// that empties out takes its card with it, so the overview never lists a dead end.
struct SettingsOverviewView<Header: View>: View {
    let section: SettingsSection
    let title: Text
    var isAvailable: (SettingsPage) -> Bool = { _ in true }
    let open: (SettingsPage) -> Void
    @ViewBuilder var header: Header

    private var groups: [[SettingsPage]] {
        section.pageGroups.map { $0.filter(isAvailable) }.filter { !$0.isEmpty }
    }

    var body: some View {
        SettingsPageScaffold {
            header
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                SettingsLinkCard(pages: group, open: open)
            }
        }
        .navigationTitle(title)
    }
}

extension SettingsOverviewView where Header == EmptyView {
    /// Fixed sections use the navigation title without a duplicate content heading.
    init(section: SettingsSection, isAvailable: @escaping (SettingsPage) -> Bool = { _ in true },
         open: @escaping (SettingsPage) -> Void) {
        let title = Text(section.title ?? .settingsGeneral)
        self.init(section: section, title: title, isAvailable: isAvailable, open: open) {
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Dock overview") {
    SettingsOverviewView(section: .dock, open: { _ in })
        .frame(width: 720, height: 640)
}
#Preview("Features overview — dark") {
    SettingsOverviewView(section: .features,
                         isAvailable: { $0 != .focusSessions && $0 != .actionTiles },
                         open: { _ in })
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 640)
}
#endif

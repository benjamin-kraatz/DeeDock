import SwiftUI
import UniformTypeIdentifiers

/// Deterministic sample content for Files previews, modeled on the mockup's tree.
///
/// Dates are anchored to the start of today so "Today, 10:24" style labels stay stable.
@MainActor
enum HubFilesPreviewData {
    static let home = URL(filePath: "/Users/benn")

    static func dataSource(empty: Bool = false) -> HubFilesMemoryDataSource {
        let source = HubFilesMemoryDataSource(home: home, available: 412_000_000_000)
        let day = Calendar.current.startOfDay(for: .now)
        func at(_ daysAgo: Double, _ hour: Double = 9, _ minute: Double = 0) -> Date {
            day.addingTimeInterval(-daysAgo * 86_400 + hour * 3_600 + minute * 60)
        }
        let mb: Int64 = 1_000_000
        for folder in ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies"] {
            source.add("/Users/benn/\(folder)", modified: at(30))
        }
        source.add("/Applications", modified: at(60))
        guard !empty else { return source }
        source.add("/Users/benn/Documents/DOKK", modified: at(0, 10, 24))
        source.add("/Users/benn/Documents/DOKK/Design", modified: at(0, 10, 24))
        source.add("/Users/benn/Documents/DOKK/Design/Concept.pdf", kind: .pdf, size: 2_400_000, modified: at(0, 10, 24))
        source.add("/Users/benn/Documents/DOKK/Design/Hub.svg", kind: .svg, size: 180_000, modified: at(1, 14, 32))
        source.add("/Users/benn/Documents/DOKK/Notes.md", kind: UTType(filenameExtension: "md") ?? .plainText,
                   size: 12_000, modified: at(1, 14, 32))
        source.add("/Users/benn/Documents/Budget 2026.xlsx", kind: UTType(filenameExtension: "xlsx") ?? .spreadsheet,
                   size: 88_000, modified: at(4))
        source.add("/Users/benn/Documents/Keynote.key", kind: .presentation, size: 31 * mb, modified: at(9))
        source.add("/Users/benn/Downloads/Screenshot.png", kind: .png, size: 1_800_000, modified: at(0, 8, 41))
        source.add("/Users/benn/Downloads/Reference.jpg", kind: .jpeg, size: 3_100_000, modified: at(1, 16, 27))
        source.add("/Users/benn/Downloads/Font.zip", kind: .zip, size: 4_800_000, modified: at(212))
        source.add("/Users/benn/Downloads/Sample.pdf", kind: .pdf, size: 1_200_000, modified: at(213))
        source.add("/Users/benn/Downloads/Lightroom export", modified: at(7))
        source.add("/Users/benn/Downloads/Lightroom export/IMG_0412.jpg", kind: .jpeg, size: 8_400_000, modified: at(7))
        source.recentItems = (source.folders["/Users/benn/Downloads"] ?? []).filter { !$0.isDirectory }
        return source
    }

    static let volumes: [HubVolumes.Volume] = [
        HubVolumes.Volume(url: URL(filePath: "/"), name: "Macintosh HD", availableBytes: 412_000_000_000,
                          totalBytes: 1_000_000_000_000, isEjectable: false, isInternal: true),
        HubVolumes.Volume(url: URL(filePath: "/Volumes/USB-Stick"), name: "USB-Stick", availableBytes: 42_000_000_000,
                          totalBytes: 64_000_000_000, isEjectable: true, isInternal: false)
    ]
}

extension HubFilesModel {
    /// A model over `HubFilesPreviewData` with the given first tab, already "visible" so panes load.
    ///
    /// Uses a throwaway defaults suite, so previews never change the user's saved layout.
    static func preview(split: Bool = true, viewMode: HubFilesViewMode = .list, emptyFolders: Bool = false,
                        firstLocation: String = "/Users/benn/Documents/DOKK/Design",
                        configure: (HubFilesModel) -> Void = { _ in }) -> HubFilesModel {
        let suite = "dokk.preview.hub.files"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let snapshot = HubFilesSnapshot(
            tabs: [
                .init(panes: [.init(location: .folder(URL(filePath: firstLocation)), sort: HubFileSort()),
                              .init(location: .folder(URL(filePath: "/Users/benn/Downloads")), sort: HubFileSort())],
                      isSplit: split, activePane: 0, viewMode: viewMode),
                .init(panes: [.init(location: .folder(URL(filePath: "/Users/benn/Downloads")), sort: HubFileSort())],
                      isSplit: false, activePane: 0, viewMode: .icons)
            ],
            selectedTab: 0, showsPreview: true)
        snapshot.save(to: defaults)
        let model = HubFilesModel(defaults: defaults, dataSource: HubFilesPreviewData.dataSource(empty: emptyFolders))
        model.previewOverrides.volumes = HubFilesPreviewData.volumes
        model.activateWithoutShell()
        model.activePane.selectWhenListed([URL(filePath: "\(firstLocation)/Concept.pdf")])
        configure(model)
        return model
    }
}

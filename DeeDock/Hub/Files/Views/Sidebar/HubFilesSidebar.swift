import SwiftUI

/// The 200 pt sidebar: Favorites (built-in places and added folders, in the person's order) and
/// Drives. Every entry is a drop target.
///
/// The current-location fill is one shared shape: choosing another place slides it there on the
/// Hub's spring instead of switching rows, like the header's tab pill. The whole column, gaps
/// included, routes drags to `HubFilesSidebarModel`, which decides between "insert here" and
/// "drop into this folder".
struct HubFilesSidebar: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme
    @Namespace private var currentFill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HubFilesSidebarFavorites(model: model, currentFill: currentFill)
                if !model.driveList.isEmpty {
                    HubFilesSidebarHeader(title: .hubFilesSidebarDrives, isFirst: false)
                    ForEach(model.driveList) { volume in
                        HubFilesDriveRow(model: model, volume: volume, currentFill: currentFill)
                            .transition(.asymmetric(insertion: .opacity,
                                                    removal: .opacity.combined(with: .offset(x: -12))))
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background {
                HubFilesInteractionRegion(interaction: HubFilesInteractions.sidebarDropArea(model: model), model: model)
            }
            .animation(HubFilesMotion.animation(.easeInOut(duration: 0.35)), value: model.driveList.map(\.id))
            .animation(HubFilesMotion.layout, value: currentLocation)
        }
        .scrollIndicators(.automatic)
        .frame(width: HubFilesMetrics.sidebarWidth)
        .background { HubFilesSidebarAnchor(role: .sidebar, sidebar: model.sidebar) }
        .background(HubFilesTheme(scheme).sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(width: 0.5)
        }
    }

    /// What the sidebar highlights; nil while search results replace the panes.
    private var currentLocation: HubFilesLocation? {
        model.isSearching ? nil : model.activePane.location
    }
}

/// The Favorites section: its header, the rows with an insertion slot where a drag points, and
/// the end slot while a drag carrying folders is over the Hub.
private struct HubFilesSidebarFavorites: View {
    let model: HubFilesModel
    let currentFill: Namespace.ID

    private enum Item: Identifiable {
        case entry(HubFilesSidebarEntry)
        case slot

        var id: HubFilesSidebarFavoritesItemID {
            switch self {
            case .entry(let entry): .entry(entry.id)
            case .slot: .slot
            }
        }
    }

    /// The rows in order without the lifted one, and the slot before the entry at `slotIndex`.
    private var items: [Item] {
        let sidebar = model.sidebar
        var items: [Item] = []
        for (index, entry) in sidebar.store.entries.enumerated() {
            if sidebar.slotIndex == index { items.append(.slot) }
            if entry.id != sidebar.liftedID { items.append(.entry(entry)) }
        }
        if let slot = sidebar.slotIndex, slot >= sidebar.store.entries.count { items.append(.slot) }
        return items
    }

    var body: some View {
        let sidebar = model.sidebar
        VStack(alignment: .leading, spacing: 0) {
            HubFilesSidebarHeader(title: .hubFilesSidebarFavorites, isFirst: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    HubFilesInteractionRegion(interaction: HubFilesInteractions.favoritesHeader(model: model), model: model)
                }
            ForEach(items) { item in
                switch item {
                case .entry(let entry):
                    HubFilesSidebarFavoriteRow(model: model, entry: entry, currentFill: currentFill)
                        .transition(.hubFilesSidebarReveal)
                case .slot:
                    HubFilesSidebarSlot(sidebar: sidebar, model: model)
                }
            }
            if let endSlot = sidebar.endSlot {
                HubFilesSidebarEndSlot(sidebar: sidebar, model: model, slot: endSlot)
            }
        }
        .background { HubFilesSidebarAnchor(role: .favorites, sidebar: sidebar) }
    }
}

/// Identity of a Favorites list item: a row, or the one insertion slot.
private enum HubFilesSidebarFavoritesItemID: Hashable {
    case entry(HubFilesSidebarEntryID)
    case slot
}

/// A sidebar section title.
private struct HubFilesSidebarHeader: View {
    let title: LocalizedStringResource
    let isFirst: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(EdgeInsets(top: isFirst ? 2 : 10, leading: 10, bottom: 6, trailing: 10))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The shared look of a sidebar entry: hover, current-location, and drop-target fills.
///
/// The current-location fill carries a matched geometry identity in `currentFill`, so it moves
/// between rows; hover and drop fills belong to their row.
struct HubFilesSidebarItemBackground: ViewModifier {
    let isCurrent: Bool
    let isHovered: Bool
    let isDropTarget: Bool
    let currentFill: Namespace.ID

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = HubFilesTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: HubStyle.rowRadius, style: .continuous)
        content
            .background {
                if isDropTarget {
                    shape.fill(theme.accentSelection)
                } else if isCurrent {
                    shape.fill(theme.selection)
                        .matchedGeometryEffect(id: "current", in: currentFill)
                } else if isHovered {
                    shape.fill(theme.chip)
                }
            }
            .overlay {
                if isDropTarget {
                    shape.strokeBorder(theme.accentLine, lineWidth: 1)
                }
            }
            .animation(HubFilesMotion.animation(.easeOut(duration: 0.15)), value: isHovered)
            .animation(HubFilesMotion.animation(.easeOut(duration: 0.15)), value: isDropTarget)
    }
}

#Preview("Sidebar", traits: .fixedLayout(width: 200, height: 460)) {
    HubFilesSidebar(model: .preview())
        .environment(\.hubFilesIconSource, .typeOnly)
}

#Preview("Sidebar · added folders and problems", traits: .fixedLayout(width: 200, height: 560)) {
    HubFilesSidebar(model: .preview(sidebarFolders: true))
        .environment(\.hubFilesIconSource, .typeOnly)
}

#Preview("Sidebar · added folders and problems, light", traits: .fixedLayout(width: 200, height: 560)) {
    HubFilesSidebar(model: .preview(sidebarFolders: true))
        .environment(\.hubFilesIconSource, .typeOnly)
        .preferredColorScheme(.light)
}

#Preview("Sidebar · drag over", traits: .fixedLayout(width: 200, height: 560)) {
    HubFilesSidebar(model: .preview(sidebarFolders: true) { model in
        model.sidebar.slotIndex = 7
        model.sidebar.slotPreview = .init(symbolName: "folder", title: "Concepts")
        model.sidebar.endSlot = .init(folderCount: 1, isTargeted: false)
    })
    .environment(\.hubFilesIconSource, .typeOnly)
}

#Preview("Sidebar · file drop into Documents", traits: .fixedLayout(width: 200, height: 560)) {
    HubFilesSidebar(model: .preview(sidebarFolders: true) { model in
        model.sidebar.intoTarget = .place(.documents)
    })
    .environment(\.hubFilesIconSource, .typeOnly)
}

#Preview("Sidebar · reordering Desktop", traits: .fixedLayout(width: 200, height: 560)) {
    HubFilesSidebar(model: .preview(sidebarFolders: true) { model in
        // Desktop is lifted into the overlay; its slot sits two rows down.
        model.sidebar.liftedID = .place(.desktop)
        model.sidebar.slotIndex = 3
        model.sidebar.slotPreview = model.sidebar.preview(for: .place(.desktop))
    })
    .environment(\.hubFilesIconSource, .typeOnly)
}

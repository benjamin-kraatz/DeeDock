import SwiftUI

/// The 200 pt sidebar: Favorites and Drives. Every entry is a drop target.
///
/// The current-location fill is one shared shape: choosing another place slides it there on the
/// Hub's spring instead of switching rows, like the header's tab pill.
struct HubFilesSidebar: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme
    @Namespace private var currentFill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HubFilesSidebarHeader(title: .hubFilesSidebarFavorites, isFirst: true)
                ForEach(HubFilesPlace.allCases) { place in
                    HubFilesSidebarRow(model: model, place: place, currentFill: currentFill)
                }
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
            .animation(HubFilesMotion.animation(.easeInOut(duration: 0.35)), value: model.driveList.map(\.id))
            .animation(HubFilesMotion.layout, value: currentLocation)
        }
        .scrollIndicators(.automatic)
        .frame(width: HubFilesMetrics.sidebarWidth)
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

import SwiftUI

/// Scroll anchors on the browse canvas. The sidebar mirrors and drives them.
enum SystemSettingsCloneSection: Hashable {
    case quickAccess
    case category(SystemSettingsCloneCategory.ID)

    var tint: SystemSettingsCloneTint {
        switch self {
        case .quickAccess: .yellow
        case let .category(id): SystemSettingsDeepLinkCatalog.category(id: id)?.tint ?? .gray
        }
    }

    /// Hue for the window's background glow. Yellow turns muddy over dark glass, so Quick Access uses blue.
    var ambientTint: SystemSettingsCloneTint {
        self == .quickAccess ? .blue : tint
    }
}

/// The whole catalog on one scrolling page: Quick Access, then every category as a grid.
///
/// One page instead of a master-detail split lets people scan everything, and `scrollPosition`
/// reports the topmost section so the sidebar can follow along.
struct SystemSettingsCloneCanvas: View {
    let quickAccess: [SystemSettingsClonePane]
    @Binding var scrolledSection: SystemSettingsCloneSection?
    let launchCounts: [String: Int]
    let open: (SystemSettingsClonePane) -> Void
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                SystemSettingsCloneQuickAccess(panes: quickAccess, launchCounts: launchCounts, open: open)
                    .id(SystemSettingsCloneSection.quickAccess)
                    .modifier(StaggeredEntrance(index: 0, isVisible: hasAppeared))
                ForEach(Array(SystemSettingsDeepLinkCatalog.categories.enumerated()), id: \.element.id) { index, category in
                    SystemSettingsCloneCategorySection(category: category, launchCounts: launchCounts, open: open)
                        .id(SystemSettingsCloneSection.category(category.id))
                        .modifier(StaggeredEntrance(index: index + 1, isVisible: hasAppeared))
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: SystemSettingsCloneMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollPosition(id: $scrolledSection, anchor: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear { hasAppeared = true }
    }
}

/// Recently opened panes, topped up with everyday ones, in a single row.
///
/// Shows only as many tiles as fit the width, so the row never wraps into a ragged second line.
private struct SystemSettingsCloneQuickAccess: View {
    let panes: [SystemSettingsClonePane]
    let launchCounts: [String: Int]
    let open: (SystemSettingsClonePane) -> Void
    @State private var rowWidth: CGFloat = 600

    private static let slotWidth: CGFloat = 80

    private var visiblePanes: ArraySlice<SystemSettingsClonePane> {
        panes.prefix(max(4, Int(rowWidth / Self.slotWidth)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SystemSettingsCloneSectionHeader(
                title: Text(.systemSettingsCloneQuickAccess),
                summary: Text(.systemSettingsCloneQuickAccessSummary),
                symbolName: "star.fill",
                tint: .yellow
            )
            HStack(alignment: .top, spacing: 2) {
                ForEach(visiblePanes) { pane in
                    SystemSettingsCloneQuickTile(pane: pane, launchCount: launchCounts[pane.id, default: 0]) {
                        open(pane)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .padding(8)
            .modifier(SystemSettingsCloneSectionSurface())
        }
    }
}

/// Header and tile grid for one category.
struct SystemSettingsCloneCategorySection: View {
    let category: SystemSettingsCloneCategory
    let launchCounts: [String: Int]
    let open: (SystemSettingsClonePane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SystemSettingsCloneSectionHeader(
                title: Text(category.title),
                summary: Text(category.summary),
                symbolName: category.symbolName,
                tint: category.tint
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: SystemSettingsCloneMetrics.tileMinimumWidth), spacing: 4)],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(category.panes) { pane in
                    SystemSettingsClonePaneTile(pane: pane, launchCount: launchCounts[pane.id, default: 0]) {
                        open(pane)
                    }
                }
            }
            .padding(8)
            .modifier(SystemSettingsCloneSectionSurface())
        }
    }
}

/// Small tinted glyph, section title, and a one-line summary.
struct SystemSettingsCloneSectionHeader: View {
    let title: Text
    let summary: Text
    let symbolName: String
    let tint: SystemSettingsCloneTint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: tint.colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 18)
                .accessibilityHidden(true)
            title
                .font(.system(size: 19, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            summary
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 6)
    }
}

/// Quiet raised card behind a section's grid.
struct SystemSettingsCloneSectionSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SystemSettingsCloneMetrics.sectionRadius, style: .continuous)
        content
            .background(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.035), in: shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 0.75) }
    }
}

/// Fades each section up into place on first appearance, a few frames after the one above.
private struct StaggeredEntrance: ViewModifier {
    let index: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.2).delay(Double(min(index, 6)) * 0.045),
                value: isVisible
            )
    }
}

#if DEBUG
#Preview("Canvas") {
    SystemSettingsCloneCanvas(
        quickAccess: SystemSettingsCloneRecents.quickAccess(from: "wifi,sound"),
        scrolledSection: .constant(nil),
        launchCounts: [:],
        open: { _ in }
    )
    .frame(width: 760, height: 720)
}
#endif

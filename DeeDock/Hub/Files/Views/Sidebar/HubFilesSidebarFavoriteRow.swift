import SwiftUI

/// A Favorites row: a built-in place or an added folder, with its accent symbol and name.
///
/// Every row opens its folder, takes drops, can be dragged to a new position or out of the
/// sidebar, and has a context menu. An added folder that is missing dims and shows a warning; one
/// on a disconnected drive dims and names the drive. Clicking either explains in a popover.
struct HubFilesSidebarFavoriteRow: View {
    let model: HubFilesModel
    let entry: HubFilesSidebarEntry
    /// The sidebar's namespace for the sliding current-location fill.
    let currentFill: Namespace.ID

    @State private var hovered = false
    /// The arrival flash the glyph last popped for; changing it replays the pop.
    @State private var popToken: Int?

    private var sidebar: HubFilesSidebarModel { model.sidebar }
    private var store: HubFilesSidebarStore { sidebar.store }
    private var title: String { store.title(for: entry) }
    private var isCurrent: Bool {
        !model.isSearching && store.location(for: entry).map(model.isCurrent) == true
    }

    private var status: HubFilesSidebarResolution.Status {
        if case .folder(let folder) = entry { return store.status(of: folder) }
        return .available
    }

    private var subtitle: String? {
        switch (status, entry) {
        case (.disconnected(let volume), _):
            String(localized: .hubFilesSidebarNotConnected(volume))
        case (.available, .folder(let folder)):
            sidebar.duplicateSubtitle(for: folder)
        default:
            nil
        }
    }

    private var arrivalToken: Int? {
        guard let flash = sidebar.flash(for: entry.id), flash.kind == .arrival else { return nil }
        return flash.token
    }

    var body: some View {
        // A folder that can't open dims its glyph and name only: the subtitle (which explains)
        // and the warning stay readable, as in the mockup.
        let dimmed = status != .available
        HStack(spacing: 10) {
            Image(systemName: HubFilesSidebarModel.symbolName(for: entry))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 19, height: 19)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: popToken) { glyph, scale in
                    glyph.scaleEffect(scale)
                } keyframes: { _ in
                    // The arrival pop: shrink, overshoot past full size, settle.
                    MoveKeyframe(0.5)
                    CubicKeyframe(1.2, duration: 0.3)
                    CubicKeyframe(1, duration: 0.25)
                }
                .opacity(dimmed ? 0.45 : 1)
            HubFilesSidebarRowTitle(title: title, subtitle: subtitle, dimmed: dimmed)
            Spacer(minLength: 0)
            if status == .missing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: HubFilesMetrics.rowHeight)
        .padding(.vertical, subtitle == nil ? 0 : 2)
        .modifier(HubFilesSidebarItemBackground(isCurrent: isCurrent, isHovered: hovered,
                                                isDropTarget: sidebar.intoTarget == entry.id, currentFill: currentFill))
        .modifier(HubFilesSidebarFlashEffect(flash: sidebar.flash(for: entry.id)))
        .opacity(sidebar.isAwaitingFlight(entry.id) ? 0 : 1)
        .background { HubFilesSidebarAnchor(role: .row(entry.id), sidebar: sidebar) }
        .overlay {
            HubFilesInteractionRegion(
                interaction: HubFilesInteractions.favorite(entry.id, model: model) { hovered = $0 },
                model: model)
        }
        .popover(isPresented: problemBinding, arrowEdge: .trailing) {
            HubFilesSidebarProblemPopover(model: model, entryID: entry.id, title: title, status: status)
        }
        .onChange(of: arrivalToken, initial: true) { _, token in
            // Rows added by a drop carry their flash from the first frame, hence `initial`.
            guard token != nil, !HubFilesMotion.reduceMotion else { return }
            popToken = token
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: subtitle ?? (status == .missing ? String(localized: .hubFilesSidebarMissingValue) : "")))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { sidebar.open(entry.id) }
        .accessibilityAction(named: Text(.hubFilesSidebarRemove)) { sidebar.remove([entry.id], method: .accessibility) }
        .accessibilityAction(named: Text(.hubFilesSidebarMoveUp)) { sidebar.move(entry.id, by: -1) }
        .accessibilityAction(named: Text(.hubFilesSidebarMoveDown)) { sidebar.move(entry.id, by: 1) }
    }

    private var problemBinding: Binding<Bool> {
        Binding { sidebar.problem == entry.id } set: { if !$0, sidebar.problem == entry.id { sidebar.problem = nil } }
    }
}

/// The row's name, with a smaller second line when it needs one (a disconnected drive, or the
/// enclosing folder when two rows share a name).
private struct HubFilesSidebarRowTitle: View {
    let title: String
    let subtitle: String?
    /// The folder can't open: the name fades with the glyph while the subtitle keeps its weight.
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 13.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(dimmed ? 0.45 : 1)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// Every row state the sidebar can show, from the deterministic preview list: places, an added
/// folder, two that share a name, one on a disconnected drive, and one that is missing.
private struct HubFilesSidebarFavoriteRowPreview: View {
    let model = HubFilesModel.preview(sidebarFolders: true)
    @Namespace private var currentFill

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.sidebar.store.entries) { entry in
                HubFilesSidebarFavoriteRow(model: model, entry: entry, currentFill: currentFill)
            }
        }
        .padding(10)
        .frame(width: HubFilesMetrics.sidebarWidth)
        .environment(\.hubFilesIconSource, .typeOnly)
    }
}

#Preview("Favorite rows") {
    HubFilesSidebarFavoriteRowPreview()
}

#Preview("Favorite rows · light") {
    HubFilesSidebarFavoriteRowPreview()
        .preferredColorScheme(.light)
}

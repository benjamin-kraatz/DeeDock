import SwiftUI

/// The open insertion slot: a preview of the row a drop will create (or where a dragged row will
/// land), outlined in the accent color.
struct HubFilesSidebarSlot: View {
    let sidebar: HubFilesSidebarModel
    let model: HubFilesModel

    var body: some View {
        HubFilesSidebarSlotPreview(preview: sidebar.slotPreview)
            .frame(height: sidebar.slotHeight)
            .background { HubFilesSidebarAnchor(role: .slot, sidebar: sidebar) }
            .overlay { HubFilesInteractionRegion(interaction: HubFilesInteractions.sidebarDropArea(model: model), model: model) }
            .transition(.hubFilesSidebarReveal)
            .accessibilityHidden(true)
    }
}

/// The dashed row that appears under Favorites while a drag carrying folders is over the Hub,
/// so people find out they can drop there. Targeted, it previews the folder it will add.
struct HubFilesSidebarEndSlot: View {
    let sidebar: HubFilesSidebarModel
    let model: HubFilesModel
    let slot: HubFilesSidebarModel.EndSlot

    var body: some View {
        ZStack {
            if slot.isTargeted {
                HubFilesSidebarSlotPreview(preview: sidebar.slotPreview)
                    .transition(.opacity)
            } else {
                HubFilesSidebarEndSlotHint(folderCount: slot.folderCount)
                    .transition(.opacity)
            }
        }
        .frame(height: HubFilesMetrics.rowHeight)
        .background { HubFilesSidebarAnchor(role: .endSlot, sidebar: sidebar) }
        .overlay { HubFilesInteractionRegion(interaction: HubFilesInteractions.sidebarDropArea(model: model), model: model) }
        .padding(.top, HubFilesSidebarMetrics.endSlotSpacing)
        .transition(.hubFilesSidebarReveal)
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.18)), value: slot.isTargeted)
    }
}

/// The accent-outlined preview inside a slot.
private struct HubFilesSidebarSlotPreview: View {
    let preview: HubFilesSidebarModel.SlotPreview?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubStyle.rowRadius, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: preview?.symbolName ?? "folder")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 19, height: 19)
            Text(verbatim: preview?.title ?? "")
                .font(.system(size: 13.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(0.75)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        // A lighter tint than a drop target's fill: this row is a promise, not a selection.
        .background(Color.accentColor.opacity(0.12), in: shape)
        .overlay { shape.strokeBorder(HubFilesTheme(scheme).accentLine, lineWidth: 1) }
    }
}

/// "Add folder here", dashed and quiet until the pointer reaches it.
private struct HubFilesSidebarEndSlotHint: View {
    let folderCount: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubStyle.rowRadius, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 19, height: 19)
            Text(folderCount > 1 ? .hubFilesSidebarDropHereCount(folderCount) : .hubFilesSidebarDropHere)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .overlay { shape.strokeBorder(HubFilesTheme(scheme).strongLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
    }
}

extension AnyTransition {
    /// A row or slot that opens from zero height (pushing the rows below down on the same spring)
    /// and fades in; removal runs it backwards with a slight slide to the left.
    static var hubFilesSidebarReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: HubFilesSidebarReveal(progress: 0, slide: 0),
                                 identity: HubFilesSidebarReveal(progress: 1, slide: 0)),
            removal: .modifier(active: HubFilesSidebarReveal(progress: 0, slide: -12),
                               identity: HubFilesSidebarReveal(progress: 1, slide: 0)))
    }
}

/// Clips content to `progress` of its height. Animatable, so the height (and the layout under it)
/// moves continuously instead of jumping.
private struct HubFilesSidebarReveal: ViewModifier, Animatable {
    var progress: CGFloat
    var slide: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, slide) }
        set { progress = newValue.first; slide = newValue.second }
    }

    func body(content: Content) -> some View {
        HubFilesHeightRevealLayout(progress: progress) {
            content.offset(x: slide * (1 - progress))
        }
        .clipShape(HubFilesRevealClip(isClipping: progress < 1))
        .opacity(Double(progress))
    }
}

/// Clips to the bounds only while a row is opening or closing. Fully open, it clips nothing, so
/// the sliding current-location fill can pass over a row's edges. The shape stays the same type
/// either way, which keeps the row's identity (and its hover state) stable.
private struct HubFilesRevealClip: Shape {
    let isClipping: Bool

    func path(in rect: CGRect) -> Path {
        Path(isClipping ? rect : rect.insetBy(dx: -10_000, dy: -10_000))
    }
}

/// Reports `progress` of its child's height and places the child at the top, clipped.
private struct HubFilesHeightRevealLayout: Layout {
    var progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * max(0, min(progress, 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

/// The end slot at rest for one and three folders, targeted, and an open insertion slot.
private struct HubFilesSidebarSlotPreviews: View {
    let model = HubFilesModel.preview { model in
        model.sidebar.slotPreview = .init(symbolName: "folder", title: "DeeDock")
    }

    var body: some View {
        VStack(spacing: 6) {
            HubFilesSidebarEndSlot(sidebar: model.sidebar, model: model,
                                   slot: .init(folderCount: 1, isTargeted: false))
            HubFilesSidebarEndSlot(sidebar: model.sidebar, model: model,
                                   slot: .init(folderCount: 3, isTargeted: false))
            HubFilesSidebarEndSlot(sidebar: model.sidebar, model: model,
                                   slot: .init(folderCount: 1, isTargeted: true))
            HubFilesSidebarSlot(sidebar: model.sidebar, model: model)
        }
        .padding(10)
        .frame(width: HubFilesMetrics.sidebarWidth)
    }
}

#Preview("Slots") {
    HubFilesSidebarSlotPreviews()
}

#Preview("Slots · light") {
    HubFilesSidebarSlotPreviews()
        .preferredColorScheme(.light)
}

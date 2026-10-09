import SwiftUI

/// Fill and stroke for rows, tiles, and column items: hover, selection (accent in the active
/// pane, gray elsewhere), drop target, and the green flash of a freshly arrived item.
struct HubFilesItemBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let isSelected: Bool
    let isActivePane: Bool
    let isHovered: Bool
    let isDropTarget: Bool
    let isFresh: Bool

    @Environment(\.colorScheme) private var scheme
    /// The fresh flash's current opacity; animated from 0.3 to 0 when the item arrives.
    @State private var flash = 0.0

    func body(content: Content) -> some View {
        let theme = HubFilesTheme(scheme)
        content
            .background(fill(theme), in: shape)
            .background(theme.fresh.opacity(flash), in: shape)
            .overlay {
                if let stroke = stroke(theme) {
                    shape.strokeBorder(stroke.color, lineWidth: stroke.width)
                }
            }
            .animation(HubFilesMotion.animation(.easeOut(duration: 0.12)), value: isHovered)
            .animation(HubFilesMotion.animation(.easeOut(duration: 0.12)), value: isDropTarget)
            .onChange(of: isFresh, initial: true) { _, fresh in
                guard fresh else { return }
                // Mockup `@keyframes fresh`: hold the green for the first 30 % of 1.6 s, then fade.
                flash = 0.3
                withAnimation(.easeOut(duration: HubFilesMotion.reduceMotion ? 0.4 : 1.1).delay(0.5)) { flash = 0 }
            }
    }

    private func fill(_ theme: HubFilesTheme) -> Color {
        if isDropTarget { return theme.accentSelection }
        if isSelected { return isActivePane ? theme.accentSelection : theme.selection }
        return isHovered ? theme.chip : .clear
    }

    private func stroke(_ theme: HubFilesTheme) -> (color: Color, width: CGFloat)? {
        if isDropTarget { return (theme.accentLine, 1.5) }
        if isSelected, isActivePane { return (theme.accentLine, 0.5) }
        return nil
    }
}

/// VoiceOver for one item: name, kind and date, selection, and Open / Quick Look actions.
struct HubFilesItemAccessibility: ViewModifier {
    let item: HubFileItem
    let isSelected: Bool
    let detail: String
    let model: HubFilesModel
    let pane: HubFilesPane?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: item.name))
            .accessibilityValue(Text(verbatim: "\(kind), \(detail)"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { open() }
            .accessibilityAction(named: Text(.hubFilesMenuOpen)) { open() }
            .accessibilityAction(named: Text(.hubFilesMenuQuickLook)) {
                select()
                model.toggleQuickLook()
            }
    }

    private var kind: String {
        item.isDirectory ? String(localized: .hubFilesKindFolder) : item.kindDescription
    }

    private func select() {
        if let pane {
            if !pane.selection.contains(item.url) { pane.click(item.url, mode: .replace) }
        } else if !model.searchSelection.contains(item.url) {
            model.clickSearchResult(item.url, mode: .replace)
        }
    }

    private func open() {
        if let pane { model.open(item, in: pane) } else { model.openSearchResult(item) }
    }
}

import SwiftUI

/// A section heading in the sidebar.
struct FlixSidebarHeader: View {
    let title: Text
    var intelligent = false

    var body: some View {
        HStack(spacing: 5) {
            if intelligent { FlixSparkle(size: 10) }
            title.lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .kerning(0.2)
        .foregroundStyle(FlixStyle.faint)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A sidebar row's glyph.
enum FlixSidebarGlyph {
    case symbol(String)
    case emoji(String)
    case sparkle
    case image(NSImage)
}

/// One sidebar entry: glyph, title, count.
///
/// The selected row's pill is shared across rows through `selectionNamespace`, so it slides from
/// the old row to the new one (``FlixMotion/pill``) instead of blinking; the sidebar animates the
/// filter change. A drop target turns accent with white text. A just-made Smart Filter is `born`:
/// a violet wash and rim that fade over 1.4 seconds.
struct FlixSidebarRow: View {
    let title: Text
    let glyph: FlixSidebarGlyph
    let count: Int?
    let selected: Bool
    var quiet = false
    var targeted = false
    var born = false
    var selectionNamespace: Namespace.ID?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.controlRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                glyphView
                    .frame(width: 16)
                    .foregroundStyle(targeted ? Color.white : quiet ? Color.secondary : Color.accentColor)
                title
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(targeted ? Color.white : quiet ? FlixStyle.faint : Color.primary)
                Spacer(minLength: 4)
                if let count {
                    Text(count, format: .number)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(targeted ? Color.white : FlixStyle.faint)
                        .contentTransition(.numericText(value: Double(count)))
                        .layoutPriority(1)
                }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                ZStack {
                    if hovered, !selected, !targeted { shape.fill(FlixStyle.hover) }
                    if selected, !targeted { selectionPill(shape) }
                    if targeted { shape.fill(Color.accentColor) }
                    if born { FlixBornHighlight(shape: shape) }
                }
            }
            .contentShape(.rect)
            .contentShape(.focusEffect, shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(FlixMotion.hover, value: hovered)
        .animation(FlixMotion.hover, value: targeted)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(count.map { Text(.flixItemCount($0)) } ?? Text(verbatim: ""))
    }

    @ViewBuilder private func selectionPill(_ shape: RoundedRectangle) -> some View {
        if let selectionNamespace {
            shape.fill(FlixStyle.chipHover).matchedGeometryEffect(id: "selection", in: selectionNamespace)
        } else {
            shape.fill(FlixStyle.chipHover)
        }
    }

    @ViewBuilder private var glyphView: some View {
        switch glyph {
        case .symbol(let name): Image(systemName: name).font(.system(size: 11.5, weight: .medium))
        case .emoji(let emoji): Text(verbatim: emoji).font(.system(size: 12))
        case .sparkle: FlixSparkle(size: 12)
        case .image(let image): Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 16, height: 16)
        }
    }
}

/// The wash on a sidebar row that was just added: violet fill and rim, fading out by itself. The
/// fade is plain opacity, so it is the same with Reduce Motion.
private struct FlixBornHighlight: View {
    let shape: RoundedRectangle
    @State private var faded = false

    var body: some View {
        shape.fill(FlixStyle.aiSoft)
            .overlay(shape.strokeBorder(FlixStyle.aiViolet, lineWidth: 1.5))
            .opacity(faded ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 1.4)) { faded = true } }
    }
}

#if DEBUG
#Preview("Sidebar rows") {
    VStack(alignment: .leading, spacing: 1) {
        FlixSidebarHeader(title: Text(verbatim: "Threads"), intelligent: true)
        FlixSidebarRow(title: Text(verbatim: "All Activity"), glyph: .symbol("circle.circle"), count: 128, selected: true) {}
        FlixSidebarRow(title: Text(verbatim: "Oak & Ash packaging and a long name"), glyph: .emoji("🌳"), count: 6,
                       selected: false) {}
        FlixSidebarRow(title: Text(verbatim: "Clients"), glyph: .symbol("folder"), count: 2, selected: false, targeted: true) {}
        FlixSidebarRow(title: Text(verbatim: "Invoices"), glyph: .emoji("🧾"), count: 3, selected: false, born: true) {}
        FlixSidebarRow(title: Text(verbatim: "Neuer intelligenter Filter …"), glyph: .sparkle, count: nil, selected: false,
                       quiet: true) {}
    }
    .padding(8)
    .frame(width: FlixStyle.sidebarWidth)
}
#endif

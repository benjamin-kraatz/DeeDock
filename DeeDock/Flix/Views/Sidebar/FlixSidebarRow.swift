import SwiftUI

/// A section heading in the sidebar.
struct FlixSidebarHeader: View {
    let title: Text
    var intelligent = false

    var body: some View {
        HStack(spacing: 5) {
            if intelligent { FlixSparkle(size: 10) }
            title
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.tertiary)
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
struct FlixSidebarRow: View {
    let title: Text
    let glyph: FlixSidebarGlyph
    let count: Int?
    let selected: Bool
    var quiet = false
    var targeted = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                glyphView
                    .frame(width: 16)
                    .foregroundStyle(targeted ? Color.white : Color.accentColor)
                title
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(targeted ? Color.white : quiet ? Color.secondary : Color.primary)
                Spacer(minLength: 4)
                if let count {
                    Text(count, format: .number)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(targeted ? Color.white : Color.secondary.opacity(0.7))
                }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(count.map { Text(.flixItemCount($0)) } ?? Text(verbatim: ""))
    }

    private var background: Color {
        if targeted { return .accentColor }
        if selected { return FlixStyle.chipHover }
        return hovered ? FlixStyle.hover : .clear
    }

    @ViewBuilder private var glyphView: some View {
        switch glyph {
        case .symbol(let name): Image(systemName: name).font(.system(size: 11, weight: .medium))
        case .emoji(let emoji): Text(verbatim: emoji).font(.system(size: 12))
        case .sparkle: FlixSparkle(size: 12)
        case .image(let image): Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 16, height: 16)
        }
    }
}

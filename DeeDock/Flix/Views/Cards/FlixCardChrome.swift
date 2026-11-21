import SwiftUI

/// A rounded card in the list: neutral, or washed with the intelligence gradient.
struct FlixCard<Content: View>: View {
    var intelligent = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Group {
                    if intelligent { shape.fill(FlixStyle.aiWash) } else { shape.fill(FlixStyle.pane) }
                }
                // A draggable card (a Thread) handles presses in a view behind this one.
                .allowsHitTesting(false)
            }
            .overlay(shape.strokeBorder(intelligent ? FlixStyle.aiStroke : FlixStyle.outline, lineWidth: 0.5)
                .allowsHitTesting(false))
            .padding(.vertical, 6)
    }
}

/// A card button: filled for the primary action, quiet otherwise. Lightens on hover, dims while
/// pressed.
struct FlixCardButton: View {
    let title: String
    var primary = false
    var intelligent = false
    /// 22 points high, for the sidebar's tip card.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).lineLimit(1)
        }
        .buttonStyle(FlixCardButtonStyle(primary: primary, intelligent: intelligent, compact: compact))
    }
}

/// The filled or quiet rounded button used on cards, sheets, and the drop question.
struct FlixCardButtonStyle: ButtonStyle {
    var primary = false
    var intelligent = false
    var compact = false
    /// Fills the width offered, for the drop question's stacked buttons.
    var expands = false
    var height: CGFloat?
    var radius: CGFloat?

    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? (compact ? 6 : FlixStyle.controlRadius), style: .continuous)
        FlixHover { hovered in
            configuration.label
                .font(.system(size: compact ? 11 : 11.5, weight: primary ? .semibold : .regular))
                .padding(.horizontal, compact ? 8 : 10)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(height: height ?? (compact ? 22 : 24))
                .foregroundStyle(primary ? Color.white : Color.primary)
                .background {
                    if primary, intelligent { shape.fill(FlixStyle.aiButtonGradient) }
                    else if primary { shape.fill(Color.accentColor) }
                    else { shape.fill(hovered && enabled ? Color.primary.opacity(0.17) : FlixStyle.chipHover) }
                }
                .brightness(primary && hovered && enabled ? 0.06 : 0)
                .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
                .contentShape(.rect)
                .contentShape(.focusEffect, shape)
                .fixedSize(horizontal: !expands, vertical: true)
        }
    }
}

/// The small ✕ that dismisses a card or closes a sheet.
struct FlixCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(hovered ? Color.primary : FlixStyle.faint)
                .frame(width: 20, height: 20)
                .background(hovered ? FlixStyle.hover : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(FlixMotion.hover, value: hovered)
        .accessibilityLabel(Text(.flixDismiss))
    }
}

/// A placeholder row that shimmers while a ✦ result loads: a violet band sweeping across every
/// 1.1 seconds. Still with Reduce Motion.
struct FlixShimmer: View {
    var reduceMotion = false
    var height: CGFloat = 40
    @State private var phase: CGFloat = -0.7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .fill(FlixStyle.chip)
            .overlay {
                if reduceMotion {
                    shape.fill(FlixStyle.aiSoft.opacity(0.5))
                } else {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, FlixStyle.aiSoft, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width)
                    }
                    .clipShape(shape)
                }
            }
            .frame(height: height)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.1 }
            }
    }
}

/// Two shimmering placeholder rows, announced to VoiceOver as loading.
struct FlixLoadingRows: View {
    var reduceMotion = false

    var body: some View {
        VStack(spacing: 0) {
            FlixShimmer(reduceMotion: reduceMotion)
            FlixShimmer(reduceMotion: reduceMotion).opacity(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.flixLoading))
    }
}

#if DEBUG
#Preview("Card chrome") {
    VStack(alignment: .leading, spacing: 8) {
        FlixCard(intelligent: true) {
            Text(verbatim: "Intelligent card").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 6) {
                FlixCardButton(title: "Open All 6", primary: true) {}
                FlixCardButton(title: "Ask Robi") {}
                FlixCardButton(title: "Make it", primary: true, intelligent: true) {}
                Spacer()
                FlixCloseButton {}
            }
        }
        FlixCard { Text(verbatim: "Neutral card").font(.system(size: 13, weight: .semibold)) }
        FlixLoadingRows()
        FlixLoadingRows(reduceMotion: true)
    }
    .padding()
    .frame(width: 500)
}
#endif

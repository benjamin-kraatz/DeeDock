import SwiftUI

/// The vertical tool strip on the stage's leading edge.
///
/// One glass capsule, one moving highlight: the selected tool's pill slides between buttons rather
/// than each button lighting up on its own, so switching tools reads as one control changing state.
struct WindowMarkupToolPalette: View {
    let document: WindowMarkupDocument
    let tint: Color
    let opaque: Bool
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ForEach(WindowMarkupTool.allCases) { tool in
                if tool == .crop || tool == .redact { Divider().frame(width: 20).padding(.vertical, 3) }
                toolButton(tool)
            }
            if document.tool == .redact {
                Divider().frame(width: 20).padding(.vertical, 3)
                redactionStyle
            }
        }
        .padding(5)
        .modifier(WindowMarkupChrome(opaque: opaque))
        .disabled(document.liveText)
        .opacity(document.liveText ? 0.45 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.15), value: document.tool)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: document.liveText)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.markupToolsAccessibility))
    }

    private func toolButton(_ tool: WindowMarkupTool) -> some View {
        let selected = document.tool == tool
        return Button {
            document.tool = tool
        } label: {
            Image(systemName: tool == .badge ? "\(document.nextBadgeNumber).circle.fill" : tool.symbol)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 34, height: 34)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tool.usesColor ? document.color.color.gradient : tint.gradient)
                            .matchedGeometryEffect(id: "selected", in: selection)
                            .shadow(color: (tool.usesColor ? document.color.color : tint).opacity(0.45), radius: 6, y: 2)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(.markupToolHelp(tool: String(localized: tool.title), key: String(tool.key).uppercased())))
        .accessibilityLabel(Text(tool.title))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// Pixelate or black out, shown only while the redact tool is active.
    private var redactionStyle: some View {
        VStack(spacing: 2) {
            ForEach(WindowMarkupRedaction.allCases) { style in
                let selected = document.redaction == style
                Button { document.redaction = style } label: {
                    Image(systemName: style == .pixelate ? "squareshape.split.3x3" : "rectangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(width: 30, height: 26)
                        .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                    in: .rect(cornerRadius: 7))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Text(style == .pixelate ? .markupRedactPixelate : .markupRedactSolid))
                .accessibilityLabel(Text(style == .pixelate ? .markupRedactPixelate : .markupRedactSolid))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
    }
}

/// Colour dots and weight, in the header. Changing either restyles a selected mark in place.
struct WindowMarkupStyleControls: View {
    let document: WindowMarkupDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var enabled: Bool {
        !document.liveText && (document.tool.usesColor || document.selectedID != nil)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(WindowMarkupColor.allCases) { color in
                    colorDot(color)
                }
            }
            weightPicker
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: enabled)
        .accessibilityElement(children: .contain)
    }

    private func colorDot(_ color: WindowMarkupColor) -> some View {
        let selected = document.color == color
        return Button {
            document.color = color
            if let id = document.selectedID { document.restyle(id, color: color) }
        } label: {
            Circle()
                .fill(color.color)
                .overlay { Circle().strokeBorder(.white.opacity(color == .white ? 0 : 0.9), lineWidth: selected ? 2 : 0) }
                .overlay { Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5) }
                .frame(width: selected ? 18 : 14, height: selected ? 18 : 14)
                .shadow(color: color.color.opacity(selected ? 0.55 : 0), radius: 5)
                .frame(width: 20, height: 20)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.35), value: selected)
        .help(Text(color.title))
        .accessibilityLabel(Text(color.title))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var weightPicker: some View {
        HStack(spacing: 1) {
            ForEach(WindowMarkupWeight.allCases) { weight in
                let selected = document.weight == weight
                Button {
                    document.weight = weight
                    if let id = document.selectedID { document.restyle(id, weight: weight) }
                } label: {
                    Circle()
                        .fill(selected ? Color.primary : Color.secondary.opacity(0.6))
                        .frame(width: 4 + 4 * weight.multiplier, height: 4 + 4 * weight.multiplier)
                        .frame(width: 22, height: 22)
                        .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(Text(weight.title))
                .accessibilityLabel(Text(weight.title))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: .capsule)
    }
}

/// Glass chrome for the markup's floating controls, opaque under Reduce Transparency.
struct WindowMarkupChrome: ViewModifier {
    let opaque: Bool
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        if opaque {
            content.background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: radius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator) }
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
        }
    }
}

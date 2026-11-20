import SwiftUI

/// A rounded card in the list: neutral, or tinted with the intelligence gradient.
struct FlixCard<Content: View>: View {
    var intelligent = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Group {
                    if intelligent {
                        shape.fill(LinearGradient(colors: [FlixStyle.aiViolet.opacity(0.12), Color.blue.opacity(0.08)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        shape.fill(FlixStyle.pane)
                    }
                }
                // A draggable card (a Thread) handles presses in a view behind this one.
                .allowsHitTesting(false)
            }
            .overlay(shape.strokeBorder(intelligent ? FlixStyle.aiStroke : Color.primary.opacity(0.12), lineWidth: 0.5)
                .allowsHitTesting(false))
            .padding(.vertical, 6)
    }
}

/// A card button: filled for the primary action, quiet otherwise.
struct FlixCardButton: View {
    let title: String
    var primary = false
    var intelligent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: primary ? .semibold : .regular))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .foregroundStyle(primary ? Color.white : .primary)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    if primary, intelligent { shape.fill(FlixStyle.aiButtonGradient) }
                    else if primary { shape.fill(Color.accentColor) }
                    else { shape.fill(FlixStyle.chipHover) }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// A placeholder row that shimmers while a ✦ result loads. Still with Reduce Motion.
struct FlixShimmer: View {
    var reduceMotion = false
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(FlixStyle.chip)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, FlixStyle.aiSoft, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

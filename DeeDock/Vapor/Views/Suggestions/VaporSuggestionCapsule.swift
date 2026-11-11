import SwiftUI

/// "4 caches in dokk-web · 2 more" with Add All and ×. While a bubble is hovered the text
/// becomes that folder's name and tag.
struct VaporSuggestionCapsule: View {
    let text: String
    let extra: Int
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let animatesEntrance: Bool
    let addAll: () -> Void
    let dismiss: () -> Void

    @State private var shown = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(verbatim: text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if extra > 0 {
                    Text(.vaporMoreSuggestions(extra))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.15), value: text)
            Button(.vaporAddAll, action: addAll)
                .buttonStyle(VaporPillButtonStyle(prominent: true))
            VaporCloseButton(diameter: 22, redOnHover: false, label: .vaporDismissSuggestions, action: dismiss)
        }
        .padding(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 5))
        .vaporGlass(in: shape, reduceTransparency: reduceTransparency)
        .overlay(shape.strokeBorder(VaporStyle.line2, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        .scaleEffect(shown || reduceMotion || !animatesEntrance ? 1 : 0.9)
        .opacity(shown || !animatesEntrance ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : VaporMotion.capsuleEnter) { shown = true }
        }
    }
}

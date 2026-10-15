import SwiftUI

/// "› Weaker matches (N)", the disclosure under Lookout's strong hits (the mockup's `.weak`). Folded by default; the
/// chevron turns a quarter when it opens. → and ← open and close it from the keyboard (`HubFilesModel+Keyboard`);
/// VoiceOver reads it as a button with its state.
struct LookoutWeakFold: View {
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(.lookoutWeakerMatches(count))
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            .foregroundStyle(hovered ? .primary : .secondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.2)), value: isExpanded)
        .animation(HubFilesMotion.quick, value: hovered)
        .accessibilityValue(Text(isExpanded ? .lookoutWeakerMatchesShown : .lookoutWeakerMatchesHidden))
        .accessibilityHint(Text(.lookoutWeakerMatchesHint))
    }
}

#Preview("Fold") {
    VStack(alignment: .leading) {
        LookoutWeakFold(count: 3, isExpanded: false) {}
        LookoutWeakFold(count: 1, isExpanded: true) {}
    }
    .frame(width: 400)
    .padding()
    .background(.regularMaterial)
}

import SwiftUI

/// Static grouped choices; only the explicit preview plays, never ten simultaneous animations.
struct BehaviorAnimationPicker: View {
    var edge: DockEdge = .bottom
    @Binding var selection: DockAnimationStyle
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DockAnimationStyle.Group.allCases, id: \.self) { group in
                Text(group.title).font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(DockAnimationStyle.allCases.filter { $0.group == group }) { style in
                        Button { selection = style } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selection == style ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection == style ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(style.title(for: edge)).font(.callout.weight(.semibold))
                                    Text(style.subtitle(for: edge)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .background(selection == style ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == style ? [.isSelected] : [])
                    }
                }
            }
        }.padding(14)
    }
}

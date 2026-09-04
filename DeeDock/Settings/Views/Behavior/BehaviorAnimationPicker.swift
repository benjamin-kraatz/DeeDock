import SwiftUI

/// Static grouped choices; only the explicit preview plays, never ten simultaneous animations.
struct BehaviorAnimationPicker: View {
    var edge: DockEdge = .bottom
    @Binding var selection: DockAnimationStyle
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DockAnimationStyle.Group.allCases, id: \.self) { group in
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(DockAnimationStyle.allCases.filter { $0.group == group }) { style in
                        Button { selection = style } label: {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(style.title(for: edge)).font(.callout.weight(.semibold))
                                    Text(style.subtitle(for: edge)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .padding(.trailing, 14)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .settingsSelectionCard(isSelected: selection == style)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == style ? [.isSelected] : [])
                    }
                }
            }
        }
        .padding(SettingsMetrics.rowInset)
    }
}

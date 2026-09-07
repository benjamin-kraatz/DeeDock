import SwiftUI

/// A native pop-up menu; the adjacent preview demonstrates the selected animation.
struct BehaviorAnimationPicker: View {
    var edge: DockEdge = .bottom
    @Binding var selection: DockAnimationStyle

    var body: some View {
        SettingsMenuRow(title: .behaviorAnimation, subtitle: selection.subtitle(for: edge),
                        selection: $selection) {
            ForEach(DockAnimationStyle.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(DockAnimationStyle.allCases.filter { $0.group == group }) { style in
                        Text(style.title(for: edge)).tag(style)
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
    }
}

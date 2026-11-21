import SwiftUI

/// What opening and dragging out do.
struct FlixBehaviorCard: View {
    @Binding var settings: FlixSettings

    var body: some View {
        SettingsCard {
            SettingsMenuRow(title: .flixSettingsOnOpen, selection: $settings.onOpen) {
                ForEach(FlixOnOpenAction.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            SettingsMenuRow(title: .flixSettingsAfterDrag, selection: $settings.afterDrag) {
                ForEach(FlixAfterDragAction.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }
}

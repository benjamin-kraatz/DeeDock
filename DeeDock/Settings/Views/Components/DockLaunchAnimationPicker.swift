import SwiftUI

/// Selecting a preset replays its production motion on deterministic artwork, without opening apps.
struct DockLaunchAnimationPicker: View {
    let edge: DockEdge
    @Binding var selection: DockLaunchAnimation
    @State private var request: Date?
    @State private var previewBusy = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(DockLaunchAnimation.allCases) { style in
                Button {
                    selection = style
                    request = Date()
                } label: {
                    VStack(spacing: 8) {
                        DockIconPresentation(size: 44, edge: edge, available: true, running: false,
                            launching: selection == style && previewBusy, keyboardSelected: false,
                            launchAnimation: style, launchRequest: selection == style ? request : nil) {
                                Image(systemName: "app.gift.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.indigo.gradient)
                            }
                            .frame(height: 76)
                            .accessibilityHidden(true)
                        Text(style.title).font(.callout.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .padding(10)
                    .settingsSelectionCard(isSelected: selection == style)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style.title))
                .accessibilityAddTraits(selection == style ? [.isSelected] : [])
            }
        }
        .padding(SettingsMetrics.rowInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.settingsLaunchAnimation))
        .task(id: request) {
            guard request != nil else { return }
            previewBusy = true
            do { try await Task.sleep(for: .seconds(selection.duration)) }
            catch { return }
            previewBusy = false
        }
    }
}

#if DEBUG
#Preview("Launch animation gallery") {
    @Previewable @State var selection = DockSettings.defaults.launchAnimation
    DockLaunchAnimationPicker(edge: .bottom, selection: $selection).frame(width: 500)
}
#endif

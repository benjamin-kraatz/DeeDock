import SwiftUI

/// The **macOS Dock** card in Settings → Behavior.
///
/// Value-driven, like `LoginItemSettingsCard`, so previews never touch the real Dock. The
/// switch is app-wide: the card looks the same on the shared defaults and on every display,
/// and it stays usable when dock settings are unreadable, because the way back must always work.
struct SystemDockTuckCard: View {
    let isOn: Bool
    let tucked: SystemDockOrientation?
    let dokkEdge: DockEdge
    var failure: LocalizedStringResource?
    var tuckAway: () -> Void = {}
    var restore: () -> Void = {}
    var dismissFailure: () -> Void = {}
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        SettingsCard(title: .systemDockTuckTitle, footnote: .systemDockTuckFootnote) {
            SettingsStackedRow {
                HStack(alignment: .center, spacing: 16) {
                    SystemDockTuckDiagram(tucked: tucked, dokkEdge: dokkEdge, reduceMotionOverride: reduceMotionOverride)
                    VStack(alignment: .leading, spacing: 10) {
                        status
                        action
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let failure {
                SettingsInlineError(message: failure, dismiss: dismissFailure)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: failure == nil)
    }

    private var statusMessage: LocalizedStringResource {
        switch tucked {
        case nil: .systemDockTuckStatusOff
        case .left? where isOn: .systemDockTuckStatusLeft
        case .right? where isOn: .systemDockTuckStatusRight
        case _?: .systemDockTuckStatusPending
        }
    }

    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: tucked == nil ? "dock.rectangle" : "checkmark.circle.fill")
                .foregroundStyle(tucked == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: tucked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var action: some View {
        if tucked == nil {
            Button(.systemDockTuckAction, systemImage: "arrow.down.right.and.arrow.up.left", action: tuckAway)
                .buttonStyle(.borderedProminent)
                .accessibilityHint(Text(.systemDockTuckActionHint))
        } else {
            Button(.systemDockRestoreAction, systemImage: "arrow.uturn.backward", action: restore)
                .buttonStyle(.bordered)
                .accessibilityHint(Text(.systemDockRestoreActionHint))
        }
    }
}

/// Binds the card to the live controller and to DOKK's main-display edge.
struct SystemDockTuckSettingsCard: View {
    let controller: SystemDockTuckController
    let dokkEdge: DockEdge

    var body: some View {
        SystemDockTuckCard(isOn: controller.isOn, tucked: controller.tuckedOrientation, dokkEdge: dokkEdge,
                           failure: controller.failure?.message,
                           tuckAway: controller.tuckAway, restore: controller.restore,
                           dismissFailure: controller.dismissFailure)
    }
}

#if DEBUG
#Preview("macOS Dock — untouched") {
    SystemDockTuckCard(isOn: false, tucked: nil, dokkEdge: .bottom).padding(24).frame(width: 620)
}

#Preview("macOS Dock — tucked away, dark") {
    SystemDockTuckCard(isOn: true, tucked: .right, dokkEdge: .left).padding(24).frame(width: 620)
        .preferredColorScheme(.dark)
}

#Preview("macOS Dock — restore failed, reduced motion") {
    SystemDockTuckCard(isOn: false, tucked: .left, dokkEdge: .bottom, failure: .systemDockRestoreFailed,
                       reduceMotionOverride: true)
        .padding(24).frame(width: 620)
}

#Preview("macOS Dock — interactive") {
    @Previewable @State var tucked: SystemDockOrientation? = nil
    SystemDockTuckCard(isOn: tucked != nil, tucked: tucked, dokkEdge: .bottom,
                       tuckAway: { tucked = .left }, restore: { tucked = nil })
        .padding(24).frame(width: 620)
}

#Preview("macOS Dock — large text") {
    SystemDockTuckCard(isOn: true, tucked: .left, dokkEdge: .bottom).padding(24).frame(width: 460)
        .dynamicTypeSize(.accessibility1)
}
#endif

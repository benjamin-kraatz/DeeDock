import SwiftUI

/// Edits the retained full-window frame. Confirmation binds the selection to that frame's source size.
///
/// The selection is made the same way it is made for Window Watch — drawn, moved, and resized
/// directly on the preview — so one gesture vocabulary covers both features. The percentages stay
/// available underneath for precision and for keyboard-only operation.
struct WindowPortalCropEditor: View {
    let state: WindowPortalState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var region = NormalizedWindowRegion()

    private var tint: Color {
        guard let icon = state.icon else { return .accentColor }
        return DockIconAccent.surface(for: icon, identity: state.appName, dark: colorScheme == .dark) ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let image = state.image {
                    WindowRegionEditor(image: image, region: $region, editable: true,
                                       scanning: false, tint: tint)
                        .frame(height: 260)
                    Text(.regionDragHint)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    WindowRegionPresetPicker(region: $region, tint: tint)
                    WindowRegionFineTuning(region: $region)
                } else {
                    ContentUnavailableView { Label(.portalUnavailable, systemImage: "macwindow.badge.plus") }
                        .frame(height: 260)
                }
                Text(.portalCropHelp)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            Divider()
            footer
        }
        .tint(tint)
        .frame(width: 520)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                       : AnyShapeStyle(.regularMaterial))
        .onAppear { region = state.crop }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = state.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "crop").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(.portalCrop)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: state.sourceName)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(reduceTransparency ? 0 : 0.18), .clear],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack {
            Button(.portalWholeWindow) { region = NormalizedWindowRegion() }
                .disabled(region.clamped == NormalizedWindowRegion())
            Spacer()
            Button(.portalCropCancel) { state.editingCrop = false }
                .keyboardShortcut(.cancelAction)
            Button(.portalCropConfirm) { state.applyCrop(region) }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.image == nil || state.source.frame == nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

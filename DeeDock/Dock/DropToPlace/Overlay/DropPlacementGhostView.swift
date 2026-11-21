import SwiftUI

/// The glass window outline that previews where an app's window will land: the armed ghost
/// while dragging, and the breathing landing pad after release.
///
/// Matches `.ghost` in `docs/mockups/drop-to-place.html`: a 12 pt continuous rounded rectangle
/// tinted with the app's accent, an inner accent stroke, a soft accent glow, a faint title-bar
/// line, and centred text. The title bar and text appear only once the ghost is wider than
/// 200 pt, so the icon-sized ghost that springs out on arming is plain glass.
struct DropPlacementGhostView: View {
    let title: String
    let subtitle: String
    let tint: Color
    let size: CGSize
    /// Landing pads pulse their glow while waiting for the window.
    var breathing = false
    var reduceMotion = false
    var reduceTransparency = false

    @State private var inhaled = false

    private static let radius: CGFloat = 12
    private static let titleBar: CGFloat = 30
    private var large: Bool { size.width > 200 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let pulse = breathing && inhaled
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.11))
                .frame(height: 1)
                .offset(y: Self.titleBar)
                .opacity(large ? 1 : 0)
            VStack(spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Self.titleBar)
            .opacity(large ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: large)
        .frame(width: max(size.width, 10), height: max(size.height, 10))
        .background { background(shape) }
        .overlay { shape.strokeBorder(tint.opacity(pulse ? 1 : 0.9), lineWidth: pulse ? 2 : 1.5) }
        .overlay { shape.stroke(.black.opacity(0.3), lineWidth: 0.5) }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.4), radius: 35, y: 24)
        .shadow(color: tint.opacity(pulse ? 0.6 : 0.35), radius: pulse ? 40 : 20)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
        .onAppear {
            guard breathing, !reduceMotion else { return }
            // Half of the mockup's 1.1 s breathe cycle each way.
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { inhaled = true }
        }
    }

    @ViewBuilder
    private func background(_ shape: RoundedRectangle) -> some View {
        let gradient = LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.12)], startPoint: .top, endPoint: .bottom)
        if reduceTransparency {
            ZStack {
                shape.fill(Color(red: 0.12, green: 0.125, blue: 0.15))
                shape.fill(gradient)
            }
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(gradient)
            }
        }
    }
}

// MARK: - Previews

/// Deterministic preview data. Copy comes from the string catalog; app names are sample values.
private enum DropPlacementGhostPreviewData {
    static let blue = Color(red: 0.44, green: 0.69, blue: 1)
    static let yellow = Color(red: 1, green: 0.85, blue: 0.29)
    static let backdrop = LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.22), Color(red: 0.04, green: 0.16, blue: 0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static func sized(_ name: String, _ width: Int, _ height: Int) -> String {
        String(localized: .dropPlaceSubtitleSize(appName: name, width: width, height: height))
    }
}

#Preview("Free · Open Here") {
    DropPlacementGhostView(title: String(localized: .dropPlaceOpenHere),
                           subtitle: DropPlacementGhostPreviewData.sized("Notes", 560, 380),
                           tint: DropPlacementGhostPreviewData.yellow, size: CGSize(width: 560, height: 380))
        .padding(60)
        .background(DropPlacementGhostPreviewData.backdrop)
}

#Preview("Memory snapped") {
    DropPlacementGhostView(title: String(localized: .dropPlaceBackWhereItWas), subtitle: "Notes",
                           tint: DropPlacementGhostPreviewData.yellow, size: CGSize(width: 400, height: 430))
        .padding(60)
        .background(DropPlacementGhostPreviewData.backdrop)
}

#Preview("Tiled · Left Half") {
    DropPlacementGhostView(title: String(localized: .dropPlaceLeftHalf), subtitle: "Mail",
                           tint: DropPlacementGhostPreviewData.blue, size: CGSize(width: 480, height: 520))
        .padding(40)
        .background(DropPlacementGhostPreviewData.backdrop)
}

#Preview("No Accessibility") {
    DropPlacementGhostView(title: String(localized: .dropPlaceOpenNormally),
                           subtitle: String(localized: .dropPlaceAccessibilityNeeded),
                           tint: DropPlacementGhostPreviewData.blue, size: CGSize(width: 520, height: 340))
        .padding(60)
        .background(DropPlacementGhostPreviewData.backdrop)
}

#Preview("Landing pad") {
    DropPlacementGhostView(title: String(localized: .dropPlaceOpening(appName: "Notes")), subtitle: "",
                           tint: DropPlacementGhostPreviewData.yellow, size: CGSize(width: 560, height: 380),
                           breathing: true)
        .padding(80)
        .background(DropPlacementGhostPreviewData.backdrop)
}

#Preview("Reduce Transparency · arming and nudged") {
    HStack(spacing: 40) {
        DropPlacementGhostView(title: String(localized: .dropPlaceMoveHere), subtitle: "",
                               tint: DropPlacementGhostPreviewData.blue, size: CGSize(width: 54, height: 54),
                               reduceTransparency: true)
        DropPlacementGhostView(title: String(localized: .dropPlaceMoveHere),
                               subtitle: String(localized: .dropPlaceSubtitleSizeNudged(appName: "Mail", width: 420, height: 300)),
                               tint: DropPlacementGhostPreviewData.blue, size: CGSize(width: 420, height: 300),
                               reduceTransparency: true)
    }
    .padding(60)
    .background(DropPlacementGhostPreviewData.backdrop)
}

import SwiftUI

/// The dashed outline of where an app's window was last time ("Last here · yesterday"), or
/// where a running app's front window is now ("Now here"). Brightens while the magnet holds.
struct DropPlacementMemoryOutlineView: View {
    let label: String
    let hot: Bool
    let size: CGSize
    var reduceMotion = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape
            .fill(.white.opacity(hot ? 0.08 : 0.03))
            .overlay { shape.strokeBorder(.white.opacity(hot ? 0.82 : 0.43), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])) }
            .overlay(alignment: .topLeading) {
                Text(verbatim: label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.69))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.35), in: .capsule)
                    .padding(.leading, 10)
                    .padding(.top, 8)
            }
            .frame(width: size.width, height: size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hot)
            .environment(\.colorScheme, .dark)
            .accessibilityHidden(true)
    }
}

#Preview("Last here and magnet") {
    HStack(spacing: 30) {
        DropPlacementMemoryOutlineView(label: String(localized: .dropPlaceLastHere(when: "yesterday")), hot: false,
                                       size: CGSize(width: 320, height: 240))
        DropPlacementMemoryOutlineView(label: String(localized: .dropPlaceLastHere(when: "3 days ago")), hot: true,
                                       size: CGSize(width: 320, height: 240))
        DropPlacementMemoryOutlineView(label: String(localized: .dropPlaceNowHere), hot: false,
                                       size: CGSize(width: 320, height: 240))
    }
    .padding(40)
    .background(LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.22), Color(red: 0.04, green: 0.16, blue: 0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
}

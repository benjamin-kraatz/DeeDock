#if DIRECT_DISTRIBUTION
import SwiftUI

/// Dismissible main-display callout for a waiting update. Layout is static for Reduce Motion.
struct UpdateAwarenessCalloutView: View {
    let version: String
    let reduceTransparency: Bool
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(UpdateAwarenessMark.fill)
                    .frame(width: 48, height: 48)
                    .background(.indigo.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(.updatesAwarenessTitle).font(.headline)
                    Text(.updatesAwarenessBody(version: version))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button(.updatesAwarenessOpen, action: open)
                    .buttonStyle(.borderedProminent)
                Button(.updatesAwarenessDismiss, action: dismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(width: 360, alignment: .leading)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 22).fill(.regularMaterial)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.12)) }
        .onExitCommand(perform: dismiss)
    }
}

#Preview("Update callout") {
    UpdateAwarenessCalloutView(version: "0.5.0", reduceTransparency: false, open: {}, dismiss: {})
        .padding()
}

#Preview("Update callout, German opaque") {
    UpdateAwarenessCalloutView(version: "0.5.0", reduceTransparency: true, open: {}, dismiss: {})
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
        .padding()
}
#endif

import SwiftUI

/// Presents a localized failure with a dismiss action, independent of the dock's services.
struct DockErrorBanner: View {
    let message: LocalizedStringResource
    /// Available viewport width, after reserving the dock's horizontal margins.
    let maximumWidth: CGFloat
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).lineLimit(3)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).accessibilityLabel(Text(.actionDismissError))
        }
        .padding(10)
        .frame(maxWidth: maximumWidth)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Narrow error banner") {
    DockErrorBanner(message: .errorOpenApp(appName: "A Longer Sample Application Name", details: "Sample launch failure"),
                    maximumWidth: 260, dismiss: {})
        .padding(20)
}
#endif

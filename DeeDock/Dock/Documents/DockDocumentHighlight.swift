import SwiftUI

/// Static document-target feedback, independent of keyboard selection and running indicators.
struct DockDocumentHighlight: View {
    let emphasized: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: emphasized ? 4 : 2, dash: [5, 3]))
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 6)
                }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Document target and spring emphasis") {
    HStack {
        DockDocumentHighlight(emphasized: false).frame(width: 52, height: 58)
        DockDocumentHighlight(emphasized: true).frame(width: 52, height: 58)
    }.padding()
}
#endif

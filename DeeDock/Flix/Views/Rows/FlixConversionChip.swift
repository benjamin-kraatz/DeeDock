import SwiftUI

/// "as PDF · 1.2 MB" on a Fits row: the file will go out as a converted copy that suits the window
/// in front. Drawn in the intelligence violet, like the drag picture's label.
struct FlixConversionChip: View {
    let text: String
    var selected = false

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(selected ? Color.white : FlixStyle.aiViolet)
            .background(selected ? Color.white.opacity(0.2) : FlixStyle.aiSoft,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}

#if DEBUG
#Preview("Conversion chip") {
    HStack {
        FlixConversionChip(text: "as PDF · 1.2 MB")
        FlixConversionChip(text: "as JPEG · 840 KB", selected: true)
            .padding(4)
            .background(Color.accentColor)
    }
    .padding()
}
#endif

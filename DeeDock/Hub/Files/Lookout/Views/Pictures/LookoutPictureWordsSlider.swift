import SwiftUI

/// How much the words typed beside a picture count against it, in the results bar of a search with both (DEE-126):
/// "Picture" on the left, "Words" on the right, a mini slider between.
///
/// It ranks again as it moves (`LookoutPictureSearch.setWordsWeight`), with both vectors already in hand, so the
/// results follow the thumb. Steps of 0.05 within `LookoutRanking.pictureWordsWeights`. It's a secondary control:
/// 10.5 pt secondary labels and a mini track filled in Lookout's accent, like the words it weighs.
///
/// VoiceOver reads it as one adjustable element, "Picture and words", whose value is how much the words count; the
/// two end labels stay out of its way.
struct LookoutPictureWordsSlider: View {
    let weight: Double
    let change: (Double) -> Void
    /// The thumb was let go at a different weight than it was picked up at.
    let commit: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// The weight when the thumb was picked up, so a click that moves nothing isn't counted.
    @State private var startWeight: Double?

    var body: some View {
        let range = LookoutRanking.pictureWordsWeights
        HStack(spacing: 6) {
            Text(.lookoutPictureWeightPicture)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { weight }, set: { change(($0 * 20).rounded() / 20) }), in: range) {
                Text(.lookoutPictureWeightLabel)
            } onEditingChanged: { editing in
                if editing {
                    startWeight = weight
                } else {
                    if let startWeight, startWeight != weight { commit() }
                    startWeight = nil
                }
            }
            .labelsHidden()
            .controlSize(.mini)
            .tint(LookoutTheme(scheme).accent)
            .frame(width: 84)
            .accessibilityValue(Text(.lookoutPictureWeightValue(Int((weight * 100).rounded()))))
            Text(.lookoutPictureWeightWords)
                .accessibilityHidden(true)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize()
        .help(Text(.lookoutPictureWeightHelp))
    }
}

#Preview("Picture–words slider") {
    @Previewable @State var weight = LookoutRanking.pictureWordsWeight
    VStack(spacing: 12) {
        LookoutPictureWordsSlider(weight: weight, change: { weight = $0 }, commit: {})
        Text(verbatim: String(format: "%.2f", weight)).monospacedDigit()
        LookoutPictureWordsSlider(weight: 0.75, change: { _ in }, commit: {})
            .environment(\.locale, Locale(identifier: "de"))
    }
    .padding(20)
    .background(.regularMaterial)
}

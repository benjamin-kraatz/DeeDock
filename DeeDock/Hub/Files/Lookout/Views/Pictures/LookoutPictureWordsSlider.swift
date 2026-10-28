import SwiftUI

/// How much the words typed beside a picture count against it, in the results bar of a search with both (DEE-126):
/// "Picture" on the left, "Words" on the right, a mini slider between.
///
/// It ranks again as it moves (`LookoutPictureSearch.setWordsWeight`), with both vectors already in hand, so the
/// results follow the thumb. Steps of 0.05 within `LookoutRanking.pictureWordsWeights`. VoiceOver reads it as one
/// adjustable element whose value is how much the words count.
struct LookoutPictureWordsSlider: View {
    let weight: Double
    let change: (Double) -> Void
    /// The thumb was let go after a move.
    let commit: () -> Void

    var body: some View {
        let range = LookoutRanking.pictureWordsWeights
        HStack(spacing: 6) {
            Text(.lookoutPictureWeightPicture)
            Slider(value: Binding(get: { weight }, set: { change(($0 * 20).rounded() / 20) }), in: range) {
                Text(.lookoutPictureWeightLabel)
            } onEditingChanged: { editing in
                if !editing { commit() }
            }
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 84)
            .accessibilityValue(Text(.lookoutPictureWeightValue(Int((weight * 100).rounded()))))
            Text(.lookoutPictureWeightWords)
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

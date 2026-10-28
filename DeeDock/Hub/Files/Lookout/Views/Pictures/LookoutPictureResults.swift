import SwiftUI

/// The results of a search with a picture, in place of the names and Lookout sections (the mockup's
/// `renderImgBody`): the results bar, a note while reading or paused, and then the promo or download card, shimmer rows
/// while the picture is read, the honest empty state, or the two groups (`LookoutPictureGroupSection`).
///
/// Like `LookoutSection`, its body is a run of sibling views, so every row is its own lazy child of the results'
/// stack and the arrow keys' scroll requests reach it.
struct LookoutPictureResults: View {
    let model: HubFilesModel
    var reduceMotion = HubFilesMotion.reduceMotion

    var body: some View {
        if let picture = model.pictureQuery {
            LookoutPictureQueryBar(picture: picture, subtitle: model.pictureSubtitle,
                                   wordsBefore: model.pictureSession.wordsBefore, words: model.pictureWords,
                                   wordsWeight: model.pictureWordsWeight, showsWordsHint: model.showsPictureWordsHint,
                                   reduceMotion: reduceMotion, changeWeight: model.setPictureWordsWeight,
                                   commitWeight: model.pictureWordsWeightCommitted) {
                model.removePicture(restoringWords: true)
                model.shell?.focusSearchField()
            }
            .lookoutArrival(index: 0, reduceMotion: reduceMotion)
            .id(picture.id)
        }
        let content = model.pictureContent
        if let notice = content.notice {
            LookoutStatusNote(pictureNotice: notice)
        }
        switch content.body {
        case .promo:
            LookoutPromoCard(title: .lookoutPicturePromoTitle, message: .lookoutPicturePromoMessage) {
                model.onSetUpLookout()
            }
            .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .download:
            LookoutDownloadCard(progress: model.lookoutDownloadProgress, message: .lookoutPictureDownloadMessage)
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .skeleton:
            LookoutSkeleton(reduceMotion: reduceMotion)
        case .unreadable:
            LookoutHonestEmpty(message: .lookoutPictureUnreadable)
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .honest:
            LookoutHonestEmpty(message: .lookoutPictureHonest)
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .groups:
            let results = model.pictureResults
            ForEach(results.groups) { group in
                LookoutPictureGroupSection(model: model, group: group, queryIsPicture: results.queryIsPicture,
                                           terms: results.terms, reduceMotion: reduceMotion)
            }
        case .nothing:
            EmptyView()
        }
    }
}

// MARK: - Previews

/// The results alone in a scrolling stack, as the Files search shows them.
private struct LookoutPictureResultsPreview: View {
    let model: HubFilesModel
    var reduceMotion = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LookoutPictureResults(model: model, reduceMotion: reduceMotion)
            }
            .padding(10)
        }
        .frame(width: 700, height: 600)
        .background(.regularMaterial)
        .environment(\.hubFilesIconSource, .typeOnly)
    }
}

#Preview("Dropped picture · two groups") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, results: LookoutPicturePreviewData.beachResults,
        wordsBefore: "dog on the beach"))
        .preferredColorScheme(.dark)
}

#Preview("Picture and words · at sunset") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, results: LookoutPicturePreviewData.sunsetResults,
        words: "at sunset"))
        .preferredColorScheme(.dark)
}

#Preview("Picture and words · German") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, results: LookoutPicturePreviewData.sunsetResults,
        words: "at sunset"))
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Find Similar on a page · light") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.similarLease, results: LookoutPicturePreviewData.leaseResults))
        .preferredColorScheme(.light)
}

#Preview("Waking the picture reader") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, phase: .waking))
}

#Preview("Reading · Reduce Motion") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.pasted, phase: .reading), reduceMotion: true)
}

#Preview("Nothing stands out · German") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, results: LookoutSimilarResults(queryIsPicture: true)))
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Not set up") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, status: .notSetUp, phase: .unavailable))
}

#Preview("Downloading") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, status: .waitingForModel, phase: .unavailable) { model in
        model.lookoutDownloadProgress = 0.42
    })
}

#Preview("Paused") {
    LookoutPictureResultsPreview(model: LookoutPicturePreviewData.model(
        picture: LookoutPicturePreviewData.dropped, status: .paused(.lowPowerMode),
        results: LookoutPicturePreviewData.beachResults))
}

import SwiftUI

/// The "Lookout · by content" section of the Files search results, under the names.
///
/// Its body is a run of sibling views, so inside the results' `LazyVStack` every row is its own lazy child and
/// `ScrollViewReader` can reach it. What shows depends on the status and the search (`LookoutSectionContent`): the
/// promo card before setup, the download card, a note while reading or paused, shimmer rows while nothing has
/// arrived, the hits, or the honest empty state.
///
/// Rows are identified by path, so the keyword-only hits stay in place when the final ones replace them: rows that
/// remain keep their place and state, new ones rise in with a 45 ms stagger (`LookoutArrival`), and the list
/// re-orders with the Hub's spring.
struct LookoutSection: View {
    let model: HubFilesModel
    var reduceMotion = HubFilesMotion.reduceMotion

    var body: some View {
        let results = model.lookoutResults
        let phase = model.lookoutPhase
        let content = LookoutSectionContent(status: model.lookoutDisplayStatus, phase: phase, results: results)
        HubFilesSearchSectionHeader(section: .lookout, count: phase == .done && content.body == .results ? results.count : nil)
            .padding(.top, 6)
        if let notice = content.notice {
            LookoutStatusNote(notice: notice)
        }
        switch content.body {
        case .promo:
            LookoutPromoCard { model.onSetUpLookout() }
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .download:
            LookoutDownloadCard(progress: model.lookoutDownloadProgress)
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .skeleton:
            LookoutSkeleton(reduceMotion: reduceMotion)
        case .results:
            LookoutResultRows(model: model, hits: results.strong, terms: results.terms, reduceMotion: reduceMotion)
            if !results.weak.isEmpty {
                LookoutWeakFold(count: results.weak.count, isExpanded: model.lookoutWeakExpanded) {
                    withAnimation(HubFilesMotion.layout) {
                        model.setLookoutWeakExpanded(!model.lookoutWeakExpanded)
                    }
                }
                if model.lookoutWeakExpanded {
                    LookoutResultRows(model: model, hits: results.weak, terms: results.terms, reduceMotion: reduceMotion)
                }
            }
        case .empty:
            LookoutHonestEmpty()
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        case .nothing:
            EmptyView()
        }
    }
}

/// A run of Lookout rows, each rising in by its position.
private struct LookoutResultRows: View {
    let model: HubFilesModel
    let hits: [LookoutHit]
    let terms: [String]
    let reduceMotion: Bool

    var body: some View {
        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
            LookoutResultRow(model: model, hit: hit, terms: terms)
                .lookoutArrival(index: index, reduceMotion: reduceMotion)
                .transition(.opacity)
                .id(HubFilesSearchResultID.lookout(hit.path))
        }
    }
}

// MARK: - Previews

/// The section alone in a scrolling stack, as the results show it.
private struct LookoutSectionPreview: View {
    let model: HubFilesModel
    var reduceMotion = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LookoutSection(model: model, reduceMotion: reduceMotion)
            }
            .padding(10)
        }
        .frame(width: 700, height: 560)
        .background(.regularMaterial)
        .environment(\.hubFilesIconSource, .typeOnly)
    }
}

#Preview("Not set up") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .notSetUp, phase: .unavailable))
}

#Preview("Downloading") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .waitingForModel, phase: .unavailable) { model in
        model.lookoutDownloadProgress = 0.42
    })
}

#Preview("Warming") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .warming))
}

#Preview("Warming · Reduce Motion") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .warming), reduceMotion: true)
}

#Preview("Keyword-only") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .keywordOnly,
                                                          results: LookoutPreviewData.keywordResults))
}

#Preview("Results · folder and weaker matches") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .done,
                                                          results: LookoutPreviewData.beachResults))
}

#Preview("Results · weaker matches open, light") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .done,
                                                          results: LookoutPreviewData.beachResults) { model in
        model.lookoutWeakExpanded = true
        model.lookoutSelection = LookoutPreviewData.receipt.path
    })
    .preferredColorScheme(.light)
}

#Preview("Indexing") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .indexing(remaining: 1_204, progress: 0.3),
                                                          phase: .done, results: LookoutPreviewData.leaseResults))
}

#Preview("Paused") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .paused(.lowPowerMode), phase: .done,
                                                          results: LookoutPreviewData.leaseResults))
}

#Preview("No results") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .done, results: .empty))
}

#Preview("No results · German") {
    LookoutSectionPreview(model: LookoutPreviewData.model(status: .ready, phase: .done, results: .empty))
        .environment(\.locale, Locale(identifier: "de"))
}

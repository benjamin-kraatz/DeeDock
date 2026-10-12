import SwiftUI

/// One group of a search with a picture: its header ("Looks like it · 5", "About what it shows · 2"), its strong
/// hits, and its own "Weaker matches" fold, or "Nothing stands out here." when nothing in it clearly fits.
///
/// The rows are Lookout's own (`LookoutResultRow`), with the match chip saying "Looks alike" or "Same subject".
struct LookoutPictureGroupSection: View {
    let model: HubFilesModel
    let group: LookoutSimilarResults.Group
    let queryIsPicture: Bool
    let reduceMotion: Bool

    var body: some View {
        let expanded = model.pictureWeakExpanded.contains(group.kind)
        HubFilesSearchSectionHeader(section: .lookoutGroup(title), count: group.count)
            .padding(.top, 6)
        if group.isEmpty {
            Text(.lookoutPictureGroupEmpty)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lookoutArrival(index: 0, reduceMotion: reduceMotion)
        }
        rows(group.strong)
        if !group.weak.isEmpty {
            LookoutWeakFold(count: group.weak.count, isExpanded: expanded) {
                withAnimation(HubFilesMotion.layout) { model.setPictureWeakExpanded(group.kind, !expanded) }
            }
            if expanded {
                rows(group.weak)
            }
        }
    }

    private func rows(_ hits: [LookoutHit]) -> some View {
        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
            LookoutResultRow(model: model, hit: hit, terms: [],
                             matchTitle: LookoutPictureWhy.matchTitle(hit: hit, group: group.kind,
                                                                      queryIsPicture: queryIsPicture))
                .lookoutArrival(index: index, reduceMotion: reduceMotion)
                .transition(.opacity)
                .id(HubFilesSearchResultID.lookout(hit.path))
        }
    }

    /// The query's own kind first: pictures that look like a picture and documents about what it shows; documents
    /// that say something similar to a document and pictures of it.
    private var title: String {
        switch (group.kind, queryIsPicture) {
        case (.pictures, true): String(localized: .lookoutPictureGroupLooksLike)
        case (.documents, true): String(localized: .lookoutPictureGroupAbout)
        case (.documents, false): String(localized: .lookoutPictureGroupSaysSimilar)
        case (.pictures, false): String(localized: .lookoutPictureGroupPicturesOf)
        }
    }
}

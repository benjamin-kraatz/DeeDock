import SwiftUI

/// **Save this page**: a slim card at the top of the list while a browser was in front when the
/// panel opened, with web links on. One press keeps the page as a link item; the card then says
/// "Saved". Saving is deliberate, so it works for any browser and any site.
struct FlixSavePageCard: View {
    let offer: FlixPageOffer
    let save: () -> Void

    private var name: String { offer.page.title ?? offer.page.host }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            FlixSiteIconView(host: offer.page.host, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(.flixSavePageTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if offer.isSaved {
                Label { Text(.flixSavePageSaved) } icon: { Image(systemName: "checkmark") }
                    .labelStyle(FlixCompactLabelStyle())
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                FlixCardButton(title: String(localized: .flixSavePageButton), primary: true, action: save)
                    .help(Text(.flixSavePageHelp(name)))
                    .accessibilityHint(Text(.flixSavePageHelp(name)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(shape.fill(FlixStyle.pane).allowsHitTesting(false))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
        .padding(.top, 6)
        .padding(.bottom, 2)
        .animation(.easeOut(duration: 0.18), value: offer.isSaved)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.flixSavePageTitle))
    }
}

#if DEBUG
#Preview("Save this page") {
    let page = FlixBrowserPage(url: URL(string: "https://docs.google.com/document/d/1abc/edit")!,
                               title: "Q4 packaging brief", privacy: .normal, browserBundleIdentifier: nil)
    VStack {
        FlixSavePageCard(offer: FlixPageOffer(page: page, isSaved: false), save: {})
        FlixSavePageCard(offer: FlixPageOffer(page: page, isSaved: true), save: {})
        FlixSavePageCard(offer: FlixPageOffer(page: FlixBrowserPage(
            url: URL(string: "https://portal.example.com/upload/documents/for-a-really-long-page-name")!, title: nil,
            privacy: .unknown, browserBundleIdentifier: nil), isSaved: false), save: {})
    }
    .padding()
    .frame(width: 500)
}
#endif

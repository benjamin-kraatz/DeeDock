import SwiftUI

/// A search results section's header, the mockup's `.sh`: a glyph, the title, "· source · count" in a quieter tone,
/// and a hairline to the edge. "Names · Spotlight · 12" and "Lookout · by content · 5".
struct HubFilesSearchSectionHeader: View {
    enum Section: Equatable {
        /// Spotlight's name results.
        case names
        /// Lookout's content results, in the Lookout accent.
        case lookout
        /// A group of a search with a picture ("Looks like it · 5"), in the Lookout accent, with no source.
        case lookoutGroup(String)
    }

    let section: Section
    /// The section's result count, or nil while it isn't known yet.
    let count: Int?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint: AnyShapeStyle = section == .names ? AnyShapeStyle(.secondary) : AnyShapeStyle(LookoutTheme(scheme).accent)
        HStack(spacing: 7) {
            glyph
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: .semibold))
            Text(verbatim: detail)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Rectangle()
                .fill(HubFilesTheme(scheme).line)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .lineLimit(1)
        .foregroundStyle(tint)
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 4, trailing: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var glyph: some View {
        switch section {
        case .names:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
        case .lookout, .lookoutGroup:
            LookoutGlyph(size: 15)
        }
    }

    private var title: String {
        switch section {
        case .names: String(localized: .lookoutSectionNames)
        case .lookout: String(localized: .lookoutSectionLookout)
        case .lookoutGroup(let title): title
        }
    }

    private var source: String? {
        switch section {
        case .names: String(localized: .lookoutSectionSpotlight)
        case .lookout: String(localized: .lookoutSectionByContent)
        case .lookoutGroup: nil
        }
    }

    private var detail: String {
        var parts = ["", source].compactMap { $0 }
        if let count { parts.append(count.formatted()) }
        return parts.joined(separator: " · ").trimmingCharacters(in: .whitespaces)
    }

    private var accessibilityLabel: String {
        var parts = [title, source].compactMap { $0 }
        if let count { parts.append(String(localized: .hubFilesResultCount(count))) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Section headers") {
    VStack(spacing: 0) {
        HubFilesSearchSectionHeader(section: .names, count: 9)
        HubFilesSearchSectionHeader(section: .lookout, count: 5)
        HubFilesSearchSectionHeader(section: .lookout, count: nil)
        HubFilesSearchSectionHeader(section: .lookoutGroup("Looks like it"), count: 4)
    }
    .frame(width: 520)
    .padding()
    .background(.regularMaterial)
}

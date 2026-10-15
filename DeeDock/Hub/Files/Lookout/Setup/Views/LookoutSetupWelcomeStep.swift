import SwiftUI

/// Step 1: the spyglass, what Lookout does, three examples, and how it handles data.
struct LookoutSetupWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                LookoutSetupHeroIcon()
                LookoutSetupTitle(.lookoutSetupWelcomeTitle)
            }
            .padding(.bottom, 16)
            LookoutSetupLead(.lookoutSetupWelcomeLead)
                .padding(.bottom, 18)
            LookoutSetupExamples()
                .padding(.bottom, 16)
            LookoutPrivacyNote()
        }
    }
}

/// The 64 pt spyglass tile with its blue-to-indigo gradient (the mockup's `.hero .spybig`).
struct LookoutSetupHeroIcon: View {
    var body: some View {
        let colors = SettingsSection.lookout.tileColors
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(stops: [.init(color: colors[0], location: 0), .init(color: colors[1], location: 0.55),
                                         .init(color: colors[2], location: 1)],
                                 startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
            .frame(width: 64, height: 64)
            .overlay { LookoutGlyph(size: 34).foregroundStyle(.white) }
            .shadow(color: Color(red: 10 / 255, green: 132 / 255, blue: 1).opacity(0.35), radius: 12, y: 8)
            .accessibilityHidden(true)
    }
}

/// Three tiles: a query in the person's own words and what it finds (the mockup's `.ex3`).
private struct LookoutSetupExamples: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LookoutSetupExampleTile(sample: .beach, query: .lookoutSetupExamplePhotoQuery,
                                    result: .lookoutSetupExamplePhotoResult)
            LookoutSetupExampleTile(sample: .screenshot, query: .lookoutSetupExampleScreenshotQuery,
                                    result: .lookoutSetupExampleScreenshotResult)
            LookoutSetupExampleTile(sample: .page, query: .lookoutSetupExamplePageQuery,
                                    result: .lookoutSetupExamplePageResult)
        }
    }
}

private struct LookoutSetupExampleTile: View {
    let sample: LookoutSampleThumbnail.Sample
    let query: LocalizedStringResource
    let result: LocalizedStringResource

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let thumb = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            LookoutSampleThumbnail(sample: sample)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .clipShape(thumb)
                .overlay { thumb.strokeBorder(LookoutTheme(scheme).strongLine, lineWidth: 0.5) }
                .padding(.bottom, 8)
            Text(query)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(result)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11.5))
        .lineSpacing(1.5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .lookoutSetupRow(radius: 12)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Welcome · dark") {
    LookoutSetupSheetPreview(step: .welcome)
        .preferredColorScheme(.dark)
}

#Preview("Welcome · light, German") {
    LookoutSetupSheetPreview(step: .welcome)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "de"))
}

import SwiftUI

/// How Lookout handles data, in one calm line beside a lock (the mockup's `.priv`): it reads only the chosen folders,
/// keeps its index on this Mac, and downloads the model once from Hugging Face without sending anything about the
/// person's files. Onboarding's welcome step and Lookout's Settings section show it.
struct LookoutPrivacyNote: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(.lookoutPrivacyNote)
                .font(.system(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(LookoutTheme(scheme).card, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The blue folder Lookout's folder lists show (the mockup's `folderIcon`). Drawn from SF Symbols rather than read
/// from the folder, so listing a protected folder never touches it.
struct LookoutFolderGlyph: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: size * 0.82))
            .foregroundStyle(Color(red: 90 / 255, green: 176 / 255, blue: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "+ Add folder…" as the mockup writes it, in the accent color.
struct LookoutAddFolderLabel: View {
    var body: some View {
        Label { Text(.lookoutSetupAddFolder) } icon: { Image(systemName: "plus").fontWeight(.medium) }
            .labelStyle(LookoutAddFolderLabelStyle())
            .foregroundStyle(Color.accentColor)
    }
}

private struct LookoutAddFolderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

#Preview("Privacy note") {
    VStack(spacing: 12) {
        LookoutPrivacyNote()
        LookoutPrivacyNote()
            .environment(\.locale, Locale(identifier: "de"))
    }
    .padding(24)
    .frame(width: 580)
    .background(.regularMaterial)
}

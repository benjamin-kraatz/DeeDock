import SwiftUI

/// Credits third-party data bundled with the app, with each license available in full.
///
/// The Homebrew cask catalog (BSD 2-Clause) supplies Robi's app descriptions. Its license requires a binary
/// distribution to reproduce the copyright notice, so the verbatim text ships as `HomebrewCaskLicense.txt`
/// and stays untranslated here.
struct AppAcknowledgementsCard: View {
    /// Verbatim license text; `nil` hides the disclosure if the resource is missing.
    var homebrewLicense: String? = Self.bundledText("HomebrewCaskLicense")

    private static let homebrewURL = URL(string: "https://formulae.brew.sh")!

    var body: some View {
        SettingsCard(title: .settingsAcknowledgementsTitle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.settingsAcknowledgementsHomebrewTitle)
                        Text(.settingsAcknowledgementsHomebrewDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: SettingsMetrics.controlSpacing)
                    Link(destination: Self.homebrewURL) { Text(.settingsAcknowledgementsSource) }
                }
                if let homebrewLicense {
                    DisclosureGroup {
                        Text(verbatim: homebrewLicense)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    } label: {
                        Text(.settingsAcknowledgementsShowLicense)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, SettingsMetrics.rowVerticalInset + 2)
        }
    }

    private static func bundledText(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

#if DEBUG
#Preview("Acknowledgements") {
    AppAcknowledgementsCard(homebrewLicense: """
        Copyright © 2013, Paul Hinze & Contributors
        All rights reserved.

        Redistribution and use in source and binary forms, with or without modification, are permitted provided \
        that the following conditions are met: …
        """)
        .padding(24)
        .frame(width: 640)
}
#endif

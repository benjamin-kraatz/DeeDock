import SwiftUI

/// Credits third-party data bundled with the app, with each license available in full.
///
/// The Homebrew cask catalog (BSD 2-Clause) supplies Robi's app descriptions, and Lucide (ISC) supplies
/// most Line glyphs. Both licenses require a binary distribution to reproduce the notice, so the verbatim
/// text ships beside the data. Simple Icons (CC0) supplies the filled brand marks and is credited the same way.
///
/// Lookout adds three: DigUp (MIT), whose indexer, ranking and crawl rules Lookout adapts; llama.cpp (MIT), the
/// embedding runtime built into its two services; and EmbeddingGemma 2 (Apache 2.0), the model it downloads.
struct AppAcknowledgementsCard: View {
    /// Verbatim license text; `nil` hides the disclosure if the resource is missing.
    var homebrewLicense: String? = Self.bundledText("HomebrewCaskLicense")
    var lucideLicense: String? = Self.bundledText("LucideLicense")
    var simpleIconsLicense: String? = Self.bundledText("SimpleIconsLicense")
    var digUpLicense: String? = Self.bundledText("DigUpLicense")
    var llamaCppLicense: String? = Self.bundledText("LlamaCppLicense")
    var embeddingGemmaLicense: String? = Self.bundledText("EmbeddingGemmaLicense")

    var body: some View {
        SettingsCard(title: .settingsAcknowledgementsTitle) {
            VStack(alignment: .leading, spacing: 14) {
                AcknowledgementCredit(title: .settingsAcknowledgementsHomebrewTitle,
                                      description: .settingsAcknowledgementsHomebrewDescription,
                                      url: URL(string: "https://formulae.brew.sh")!,
                                      license: homebrewLicense)
                AcknowledgementCredit(title: .settingsAcknowledgementsLucideTitle,
                                      description: .settingsAcknowledgementsLucideDescription,
                                      url: URL(string: "https://lucide.dev")!,
                                      license: lucideLicense)
                AcknowledgementCredit(title: .settingsAcknowledgementsSimpleIconsTitle,
                                      description: .settingsAcknowledgementsSimpleIconsDescription,
                                      url: URL(string: "https://simpleicons.org")!,
                                      license: simpleIconsLicense)
                AcknowledgementCredit(title: .settingsAcknowledgementsDigUpTitle,
                                      description: .settingsAcknowledgementsDigUpDescription,
                                      url: URL(string: "https://github.com/ARahim3/DigUp")!,
                                      license: digUpLicense)
                AcknowledgementCredit(title: .settingsAcknowledgementsLlamaCppTitle,
                                      description: .settingsAcknowledgementsLlamaCppDescription,
                                      url: URL(string: "https://github.com/ggml-org/llama.cpp")!,
                                      license: llamaCppLicense)
                AcknowledgementCredit(title: .settingsAcknowledgementsEmbeddingGemmaTitle,
                                      description: .settingsAcknowledgementsEmbeddingGemmaDescription,
                                      url: URL(string: "https://huggingface.co/google/embeddinggemma-2")!,
                                      license: embeddingGemmaLicense)
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, SettingsMetrics.rowVerticalInset + 2)
        }
    }

    /// One credited source: its name, what DOKK uses it for, a link, and the verbatim license.
    private struct AcknowledgementCredit: View {
        let title: LocalizedStringResource
        let description: LocalizedStringResource
        let url: URL
        let license: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: SettingsMetrics.controlSpacing)
                    Link(destination: url) { Text(.settingsAcknowledgementsSource) }
                }
                if let license {
                    DisclosureGroup {
                        Text(verbatim: license)
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
        """, lucideLicense: "ISC License\n\nCopyright (c) Lucide Icons and Contributors",
        simpleIconsLicense: "CC0 1.0 Universal", digUpLicense: "MIT License\n\nCopyright (c) 2026 Abdur Rahim",
        llamaCppLicense: "MIT License\n\nCopyright (c) 2023-2026 The ggml authors",
        embeddingGemmaLicense: "EmbeddingGemma 2, by Google DeepMind\n\nApache License, Version 2.0")
        .padding(24)
        .frame(width: 640)
}
#endif

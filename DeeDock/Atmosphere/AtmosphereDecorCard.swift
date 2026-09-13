import SwiftUI

/// The optional Image Playground corner décor: current thumbnail, create, and remove.
struct AtmosphereDecorCard: View {
    let image: NSImage?
    let failed: Bool
    let generate: () -> Void
    let remove: () -> Void

    private var thumbnailShape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    var body: some View {
        SettingsCard {
            SettingsRow(title: .atmosphereDecorLabel) {
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(thumbnailShape)
                            .overlay(thumbnailShape.strokeBorder(.separator, lineWidth: 0.5))
                            .accessibilityHidden(true)
                        Button(action: remove) {
                            Label(.atmosphereRemoveDecor, systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(Text(.atmosphereRemoveDecor))
                    }
                    Button(.atmosphereGenerateDecor, systemImage: "wand.and.sparkles", action: generate)
                }
            }
            if failed {
                SettingsInlineError(message: .atmosphereDecorError)
            }
        }
    }
}

#if DEBUG
#Preview("Décor") {
    VStack(spacing: SettingsMetrics.cardSpacing) {
        AtmosphereDecorCard(image: nil, failed: false, generate: {}, remove: {})
        AtmosphereDecorCard(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil),
                            failed: true, generate: {}, remove: {})
    }
    .padding(24)
    .frame(width: 620)
}
#endif

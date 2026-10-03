import SwiftUI

/// Evaluation-only knobs for the Ice Blocks material, stored app-wide in user defaults rather
/// than in `DockSettings`. They exist so the look can be dialled in on a real desktop; a
/// shipped style would bake the chosen values in and drop this file.
enum DockIceTuning {
    /// Colour wash over the clear glass, in percent.
    static let tintKey = "iceBlocks.tint"
    static let tintDefault = 12.0
    /// Dark smoke under the wash, in percent. Zero leaves the glass fully clear.
    static let shadeKey = "iceBlocks.shade"
    static let shadeDefault = 0.0
    /// Strength of the rim glow, pooled light, and halo, in percent.
    static let glowKey = "iceBlocks.glow"
    static let glowDefault = 60.0
    /// Cloudy haze just inside the rim, in percent. Zero leaves the faces as clear as the middle.
    static let frostKey = "iceBlocks.frost"
    static let frostDefault = 20.0
    /// Raw `DockIceGlassMode`.
    static let glassKey = "iceBlocks.glassMode"
    static let glassDefault = DockIceGlassMode.edges.rawValue
    /// Whether blocks redraw a live screen capture of their backdrop through the refraction
    /// shader. Replaces system glass while on.
    static let refractionKey = "iceBlocks.refraction"
    /// How far the rim displaces the backdrop, in points. Negative bends toward the middle.
    static let refractionStrengthKey = "iceBlocks.refractionStrength"
    static let refractionStrengthDefault = 14.0
    /// Upper bound on captured frames per second. An unchanged screen delivers none.
    static let refractionRateKey = "iceBlocks.refractionRate"
    static let refractionRateDefault = 30.0
}

/// Where a block uses system glass. Glass bends the backdrop but also blurs it, even in its
/// clear variant, and the blur cannot be switched off. Confining it to the rim keeps the
/// middle of the block sharp while the edges still refract.
enum DockIceGlassMode: Int, CaseIterable {
    case none, edges, full

    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .none, title: .iceTuningGlassOff, symbol: "square.dashed"),
         SettingsOption(value: .edges, title: .iceTuningGlassEdges, symbol: "square"),
         SettingsOption(value: .full, title: .iceTuningGlassFull, symbol: "square.fill")]
    }
}

/// Live sliders for `DockIceTuning`, shown only while Ice Blocks is selected.
struct DockIceTuningCard: View {
    @AppStorage(DockIceTuning.tintKey) private var tint = DockIceTuning.tintDefault
    @AppStorage(DockIceTuning.shadeKey) private var shade = DockIceTuning.shadeDefault
    @AppStorage(DockIceTuning.glowKey) private var glow = DockIceTuning.glowDefault
    @AppStorage(DockIceTuning.frostKey) private var frost = DockIceTuning.frostDefault
    @AppStorage(DockIceTuning.glassKey) private var glass = DockIceTuning.glassDefault

    var body: some View {
        SettingsCard(title: .iceTuningTitle, footnote: .iceTuningHelp) {
            SettingsSliderRow(title: .iceTuningTint, unit: .settingsPercent, value: $tint, range: 0...60, step: 1,
                              minimumSymbol: "drop", maximumSymbol: "drop.fill",
                              defaultValue: DockIceTuning.tintDefault)
            SettingsSliderRow(title: .iceTuningShade, unit: .settingsPercent, value: $shade, range: 0...80, step: 1,
                              minimumSymbol: "circle", maximumSymbol: "circle.fill",
                              defaultValue: DockIceTuning.shadeDefault)
            SettingsSliderRow(title: .iceTuningGlow, unit: .settingsPercent, value: $glow, range: 0...100, step: 1,
                              minimumSymbol: "light.min", maximumSymbol: "light.max",
                              defaultValue: DockIceTuning.glowDefault)
            SettingsSliderRow(title: .iceTuningFrost, unit: .settingsPercent, value: $frost, range: 0...100, step: 1,
                              minimumSymbol: "snowflake.slash", maximumSymbol: "snowflake",
                              defaultValue: DockIceTuning.frostDefault)
            SettingsPickerRow(title: .iceTuningGlass, options: DockIceGlassMode.settingsOptions,
                              selection: Binding(get: { DockIceGlassMode(rawValue: glass) ?? .edges },
                                                 set: { glass = $0.rawValue }))
        }
    }
}

/// Controls and a cost readout for the screen-capture refraction experiment.
struct DockIceRefractionCard: View {
    @AppStorage(DockIceTuning.refractionKey) private var enabled = false
    @AppStorage(DockIceTuning.refractionStrengthKey) private var strength = DockIceTuning.refractionStrengthDefault
    @AppStorage(DockIceTuning.refractionRateKey) private var rate = DockIceTuning.refractionRateDefault
    private var stats: DockIceBackdropStats { .shared }

    var body: some View {
        SettingsCard(title: .iceRefractionTitle, footnote: .iceRefractionHelp) {
            SettingsToggleRow(title: .iceRefractionEnabled, isOn: $enabled)
            SettingsSliderRow(title: .iceRefractionStrength, unit: .settingsPoints, value: $strength,
                              range: -40...40, step: 1, minimumSymbol: "arrow.down.right.and.arrow.up.left",
                              maximumSymbol: "arrow.up.left.and.arrow.down.right",
                              defaultValue: DockIceTuning.refractionStrengthDefault)
            SettingsSliderRow(title: .iceRefractionRate, unit: .iceRefractionRateUnit, value: $rate,
                              range: 5...60, step: 5, minimumSymbol: "tortoise", maximumSymbol: "hare",
                              defaultValue: DockIceTuning.refractionRateDefault)
            if enabled {
                Group {
                    if let frames = stats.framesPerSecond {
                        Text(.iceRefractionStats(frames: frames,
                                                 cost: stats.conversionMilliseconds.formatted(.number.precision(.fractionLength(2)))))
                    } else {
                        Text(.iceRefractionIdle)
                    }
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsMetrics.rowInset).padding(.vertical, 8)
            }
        }
    }
}

#if DEBUG
#Preview("Ice tuning card") {
    VStack(spacing: 16) {
        DockIceTuningCard()
        DockIceRefractionCard()
    }
    .padding(24).frame(width: 560)
}
#endif

import SwiftUI

/// The per-icon inputs to the Metal running indicators.
///
/// `seed` selects one point in each shader's variation space — lobe counts, spin direction,
/// facet count, phase — so two adjacent icons never draw the same figure. It is derived from
/// the application's stable identity rather than a counter, so an app keeps the same aura
/// across relaunches, reordering, and machines.
///
/// `accent` is the artwork's own dominant hue, used to tint the light that the shader has
/// already sampled from the icon. It is `nil` for achromatic artwork, which lets each style
/// fall back to its own palette instead of glowing white.
struct DockIndicatorVariant: Equatable {
    var seed: Double
    var accent: Color?

    /// The inert variation used by samples that have no application identity.
    static let neutral = DockIndicatorVariant(seed: 0.5, accent: nil)

    init(seed: Double, accent: Color? = nil) {
        self.seed = seed
        self.accent = accent
    }

    init(identity: String, accent: Color? = nil) {
        self.init(seed: Self.seed(for: identity), accent: accent)
    }

    /// One stable pseudo-random draw in `[0, 1)` for an independent dimension of the
    /// variation. `salt` separates the draws; the same seed and salt always agree, and this
    /// deliberately matches the shaders' `hash11` so drawn and Metal styles vary alike.
    func draw(_ salt: Int) -> Double {
        let value = sin(seed * 127.1 + Double(salt) * 311.7) * 43_758.545_312_3
        return value - value.rounded(.down)
    }

    /// FNV-1a over the identity's UTF-8, mapped into `[0, 1)`.
    ///
    /// `Hashable` is deliberately not used: its per-process seed would hand the same app a
    /// different aura on every launch, which is exactly what this value has to prevent.
    static func seed(for identity: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        // Keep the 53 bits a Double can hold exactly, so the mapping is uniform and stable.
        return Double(hash >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

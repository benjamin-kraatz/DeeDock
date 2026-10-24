import SwiftUI

/// The sheet's surface: frosted material over the Hub's glass, or the mockup's opaque `--sheet` color
/// (`#23242b` dark, `#f7f7f9` light) under Reduce Transparency.
///
/// The done view's trash badge draws the same surface, so it reads as a cut-out of the sheet rather than a
/// second layer of glass.
struct HubUninstallSurface<S: Shape>: View {
    let shape: S
    let opaque: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if opaque {
            shape.fill(colorScheme == .dark ? Color(red: 35 / 255, green: 36 / 255, blue: 43 / 255)
                : Color(red: 247 / 255, green: 247 / 255, blue: 249 / 255))
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

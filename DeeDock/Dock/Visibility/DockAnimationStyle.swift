import Foundation

/// Semantic persistence identifiers, independent of playful localized display names.
enum DockAnimationStyle: String, Codable, CaseIterable, Identifiable {
    case slideFade, slide, fade, liftFade, leftFade, rightFade, scaleFade, verticalWipe, horizontalWipe, bounceFade
    var id: Self { self }
    enum Group: CaseIterable { case smooth, scenic, dramatic }
    var group: Group {
        switch self {
        case .slideFade, .slide, .fade: .smooth
        case .liftFade, .leftFade, .rightFade: .scenic
        case .scaleFade, .verticalWipe, .horizontalWipe, .bounceFade: .dramatic
        }
    }
}

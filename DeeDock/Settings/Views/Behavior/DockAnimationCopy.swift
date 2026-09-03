import Foundation

/// Localized presentation stays separate from semantic animation identifiers and geometry.
extension DockAnimationStyle {
    var title: LocalizedStringResource {
        switch self {
        case .slideFade: .animationSlideFadeTitle
        case .slide: .animationSlideTitle
        case .fade: .animationFadeTitle
        case .liftFade: .animationLiftFadeTitle
        case .leftFade: .animationLeftFadeTitle
        case .rightFade: .animationRightFadeTitle
        case .scaleFade: .animationScaleFadeTitle
        case .verticalWipe: .animationVerticalWipeTitle
        case .horizontalWipe: .animationHorizontalWipeTitle
        case .bounceFade: .animationBounceFadeTitle
        }
    }
    var subtitle: LocalizedStringResource {
        switch self {
        case .slideFade: .animationSlideFadeSubtitle
        case .slide: .animationSlideSubtitle
        case .fade: .animationFadeSubtitle
        case .liftFade: .animationLiftFadeSubtitle
        case .leftFade: .animationLeftFadeSubtitle
        case .rightFade: .animationRightFadeSubtitle
        case .scaleFade: .animationScaleFadeSubtitle
        case .verticalWipe: .animationVerticalWipeSubtitle
        case .horizontalWipe: .animationHorizontalWipeSubtitle
        case .bounceFade: .animationBounceFadeSubtitle
        }
    }
}

extension DockAnimationStyle.Group {
    var title: LocalizedStringResource {
        switch self {
        case .smooth: .animationGroupSmooth
        case .scenic: .animationGroupScenic
        case .dramatic: .animationGroupDramatic
        }
    }
}

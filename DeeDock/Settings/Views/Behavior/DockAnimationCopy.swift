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

extension DockAnimationStyle {
    func title(for edge: DockEdge) -> LocalizedStringResource {
        guard edge.isVertical else { return title }
        switch self {
        case .liftFade: return .animationSideLiftTitle
        case .leftFade: return .animationSideStartTitle
        case .rightFade: return .animationSideEndTitle
        default: return title
        }
    }
    func subtitle(for edge: DockEdge) -> LocalizedStringResource {
        guard edge.isVertical else { return subtitle }
        switch self {
        case .slideFade: return .animationSideSlideFadeSubtitle
        case .slide: return .animationSideSlideSubtitle
        case .fade: return subtitle
        case .liftFade: return .animationSideLiftSubtitle
        case .leftFade: return .animationSideStartSubtitle
        case .rightFade: return .animationSideEndSubtitle
        case .scaleFade: return .animationSideScaleSubtitle
        case .verticalWipe: return .animationSideWipeSubtitle
        case .horizontalWipe: return .animationSideSqueezeSubtitle
        case .bounceFade: return .animationSideBounceSubtitle
        }
    }
}

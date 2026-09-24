import CoreGraphics
import Observation
import SwiftUI

/// One window image travelling between its Peek card and the staged hero frame.
///
/// Frames are in the stage panel's top-left-origin space. The view lays the image out once at
/// `hero` and reaches every other pose with a transform, so the flight animates scale and offset
/// only and never re-lays out a full-size image per frame.
@MainActor @Observable
final class WindowPeekExhibit: Identifiable {
    /// Distinct per staging, so a card re-staged while its previous exhibit fades out is a new view.
    let id = UUID()
    let token: ApplicationWindowToken
    let title: String
    /// The strip thumbnail, shown immediately so the flight never waits for a capture.
    let preview: CGImage
    /// The on-demand capture sized for `hero`; it crossfades over `preview` when it arrives.
    var detail: CGImage?
    /// Where the card's artwork sits; `nil` when unknown, which falls back to fade and scale.
    let source: CGRect?
    let hero: CGRect
    /// Reduce Motion replaces the shared-element flight with fade and scale.
    let reduceMotion: Bool
    var lifted = false
    var leaving = false
    /// The real window's frame after a click selected it; the exhibit flies there to become the window.
    /// The stage window itself then fades out, so the exhibit needs no vanishing pose of its own.
    var landing: CGRect?

    init(token: ApplicationWindowToken, title: String, preview: CGImage, detail: CGImage? = nil,
         source: CGRect?, hero: CGRect, reduceMotion: Bool) {
        self.token = token
        self.title = title
        self.preview = preview
        self.detail = detail
        self.source = source
        self.hero = hero
        self.reduceMotion = reduceMotion
    }

    var liftAnimation: Animation {
        morphs ? .spring(duration: 0.36, bounce: 0.12) : .easeOut(duration: 0.18)
    }

    /// Whether this exhibit flies from its card, rather than fading in at the hero frame.
    var morphs: Bool { source != nil && !reduceMotion }

    /// The transform that places the hero-sized layout at its current pose, anchored top-leading.
    var pose: WindowPeekExhibitPose {
        if let landing {
            return .placing(hero: hero, at: landing, cornerRadius: WindowPeekExhibitPose.windowCornerRadius)
        }
        if leaving { return .settled(hero: hero, scale: 0.97, opacity: 0) }
        if lifted { return .settled(hero: hero, scale: 1, opacity: 1) }
        guard morphs, let source else { return .settled(hero: hero, scale: 0.94, opacity: 0) }
        return .placing(hero: hero, at: source, cornerRadius: WindowPeekExhibitPose.cardCornerRadius)
    }
}

/// A scale, offset, opacity, and clip radius applied to an exhibit laid out at its hero frame.
nonisolated struct WindowPeekExhibitPose: Equatable, Sendable {
    let scale: CGSize
    let offset: CGSize
    let opacity: Double
    let cornerRadius: CGFloat

    /// Corner radius the card artwork uses; the flight starts from it so the hand-off is seamless.
    static let cardCornerRadius: CGFloat = 7
    static let heroCornerRadius: CGFloat = 14
    /// Approximates a standard macOS window's corners, where a landing ends.
    static let windowCornerRadius: CGFloat = 16

    /// Maps the hero-sized layout exactly onto `rect`, showing `cornerRadius` at that size.
    static func placing(hero: CGRect, at rect: CGRect, cornerRadius: CGFloat) -> Self {
        let scale = CGSize(width: rect.width / max(1, hero.width), height: rect.height / max(1, hero.height))
        return Self(scale: scale, offset: CGSize(width: rect.minX - hero.minX, height: rect.minY - hero.minY),
                    opacity: 1,
                    // Clipping happens before scaling, so divide to land on the requested radius.
                    cornerRadius: cornerRadius / max(0.01, min(scale.width, scale.height)))
    }

    /// A uniform scale about the hero's center, expressed with the top-leading anchor the flight uses.
    static func settled(hero: CGRect, scale: CGFloat, opacity: Double) -> Self {
        Self(scale: CGSize(width: scale, height: scale),
             offset: CGSize(width: (1 - scale) * hero.width / 2, height: (1 - scale) * hero.height / 2),
             opacity: opacity, cornerRadius: heroCornerRadius)
    }
}

/// Everything the stage panel draws: a dim with a hole for the Peek panel, plus the exhibits.
@MainActor @Observable
final class WindowPeekStage {
    /// More than one only while a replaced exhibit finishes fading out.
    var exhibits: [WindowPeekExhibit] = []
    /// The Peek panel's frame; the dim leaves it undimmed so the cards stay readable.
    var cutout: CGRect = .zero
    var dimmed = false
}

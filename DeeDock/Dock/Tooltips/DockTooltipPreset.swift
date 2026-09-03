import SwiftUI

/// Complete, versioned choices: selecting a tile sets design, placement, delay, and entrance together.
enum DockTooltipPreset: String, Codable, CaseIterable, Identifiable {
    case classic, glassPill, compact, plain, bold, outline, accent, speechBubble, nameCard
    case leadingTag, trailingTag, leadingOutline, trailingPill, dockCaption, dockTitle, lift, pop, spectrum, off
    var id: Self { self }
    enum Placement { case inward, before, after, dockCenter }
    enum Entrance { case instant, fade, lift, slide, pop, crossfade }
    var placement: Placement {
        switch self {
        case .leadingTag, .leadingOutline: .before
        case .trailingTag, .trailingPill: .after
        case .dockCaption, .dockTitle: .dockCenter
        default: .inward
        }
    }
    var delay: Double {
        switch self {
        case .classic, .plain, .dockCaption, .off: 0
        case .glassPill, .bold, .accent, .leadingTag, .trailingTag, .pop: 0.15
        case .compact: 0.35
        case .nameCard: 0.4
        case .leadingOutline, .trailingPill: 0.3
        default: 0.2
        }
    }
    var entrance: Entrance {
        switch self {
        case .classic, .plain, .off: .instant
        case .speechBubble, .lift: .lift
        case .leadingTag, .trailingTag: .slide
        case .pop: .pop
        case .dockCaption, .dockTitle: .crossfade
        default: .fade
        }
    }
    func animation(reduceMotion: Bool) -> Animation? {
        guard entrance != .instant else { return nil }
        return .easeOut(duration: reduceMotion ? 0.1 : (entrance == .pop ? 0.18 : 0.15))
    }
    func transition(edge: DockEdge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch entrance {
        case .instant: return .identity
        case .lift:
            let offset = edge.offset(CGSize(width: 0, height: 6))
            return .offset(x: offset.width, y: offset.height).combined(with: .opacity)
        case .slide:
            let offset = edge.offset(CGSize(width: placement == .before ? 6 : -6, height: 0))
            return .offset(x: offset.width, y: offset.height).combined(with: .opacity)
        case .pop: return .scale(scale: 0.94).combined(with: .opacity)
        default: return .opacity
        }
    }
    var title: LocalizedStringResource {
        switch self {
        case .classic: .tooltipClassic
        case .glassPill: .tooltipGlassPill
        case .compact: .tooltipCompact
        case .plain: .tooltipPlain
        case .bold: .tooltipBold
        case .outline: .tooltipOutline
        case .accent: .tooltipAccent
        case .speechBubble: .tooltipSpeechBubble
        case .nameCard: .tooltipNameCard
        case .leadingTag: .tooltipLeadingTag
        case .trailingTag: .tooltipTrailingTag
        case .leadingOutline: .tooltipLeadingOutline
        case .trailingPill: .tooltipTrailingPill
        case .dockCaption: .tooltipDockCaption
        case .dockTitle: .tooltipDockTitle
        case .lift: .tooltipLift
        case .pop: .tooltipPop
        case .spectrum: .tooltipSpectrum
        case .off: .tooltipOff
        }
    }
    var subtitle: LocalizedStringResource {
        switch self {
        case .classic: .tooltipClassicDetail
        case .glassPill: .tooltipGlassPillDetail
        case .compact: .tooltipCompactDetail
        case .plain: .tooltipPlainDetail
        case .bold: .tooltipBoldDetail
        case .outline: .tooltipOutlineDetail
        case .accent: .tooltipAccentDetail
        case .speechBubble: .tooltipSpeechBubbleDetail
        case .nameCard: .tooltipNameCardDetail
        case .leadingTag: .tooltipLeadingTagDetail
        case .trailingTag: .tooltipTrailingTagDetail
        case .leadingOutline: .tooltipLeadingOutlineDetail
        case .trailingPill: .tooltipTrailingPillDetail
        case .dockCaption: .tooltipDockCaptionDetail
        case .dockTitle: .tooltipDockTitleDetail
        case .lift: .tooltipLiftDetail
        case .pop: .tooltipPopDetail
        case .spectrum: .tooltipSpectrumDetail
        case .off: .tooltipOffDetail
        }
    }
}

import AppKit
import SwiftUI

enum Layout {
    static let tabHeight: CGFloat = 42
    static let flare: CGFloat = 11
    static let shadowMargin: CGFloat = 10
    static let cardWidth: CGFloat = 470
}

@MainActor
final class CompanionModel: ObservableObject {
    enum Phase { case idle, awake, selecting, prompting, thinking, answered }
    enum Placement { case above, inside }

    @Published var phase: Phase = .idle
    @Published var placement: Placement = .above
    @Published var tint = Color(white: 0.96)
    @Published var tintIsDark = false
    @Published var context: CompanionContext?
    @Published var prompt = ""
    @Published var answer = ""
    @Published var proposedAction: String?
    @Published var toast: String?
    @Published var appName = "App"
    @Published var busyLabel: String?
    var canReplace = false

    var ink: Color { tintIsDark ? .white : Color(red: 0.13, green: 0.12, blue: 0.17) }
    var rim: Color { tintIsDark ? .white.opacity(0.14) : .black.opacity(0.10) }
    var isBar: Bool { [.prompting, .thinking, .answered].contains(phase) }
    var showsCard: Bool { phase == .thinking || phase == .answered }

    var tabWidth: CGFloat {
        switch phase {
        case .idle, .awake: 108
        case .selecting: 330
        case .prompting, .thinking, .answered: Layout.cardWidth + 2 * Layout.flare
        }
    }

    /// Panel size per phase. The panel is resized before a grow and after a shrink so the
    /// transparent margin never sits over the target window longer than needed.
    var panelSize: CGSize {
        let width = max(tabWidth, phase == .selecting ? 330 : 0) + 2 * Layout.shadowMargin
        var height = Layout.tabHeight + Layout.shadowMargin
        if phase == .prompting { height += 46 }
        if showsCard { height += 300 }
        return CGSize(width: width, height: height)
    }
}

/// High-frequency eye state lives apart so 60 Hz pointer updates only redraw the face.
@MainActor
final class EyeModel: ObservableObject {
    @Published var pupil: CGSize = .zero
    @Published var blink = false
}

struct CompanionActions {
    var tapFace: () -> Void = {}
    var submit: (String) -> Void = { _ in }
    var copy: () -> Void = {}
    var replace: () -> Void = {}
    var paste: () -> Void = {}
    var runProposed: () -> Void = {}
    var dismiss: () -> Void = {}
}

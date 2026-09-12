import Foundation

/// Persisted gossip style, independent of Sims animation strength and AI consent.
nonisolated enum DockRumourIntensity: Int, Codable, CaseIterable, Sendable {
    case lightChatter = 0, loudWhispering, egregiousEchoing

    var title: LocalizedStringResource {
        switch self {
        case .lightChatter: .simsGossipLight
        case .loudWhispering: .simsGossipLoud
        case .egregiousEchoing: .simsGossipEgregious
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .lightChatter: .simsGossipLightHelp
        case .loudWhispering: .simsGossipLoudHelp
        case .egregiousEchoing: .simsGossipEgregiousHelp
        }
    }

    func participantCount(available: Int) -> Int {
        min(available, self == .egregiousEchoing ? 5 : 2)
    }

    func turnCount(available: Int) -> Int {
        switch self {
        case .lightChatter: 2
        case .loudWhispering: 3
        case .egregiousEchoing: participantCount(available: available) * 2
        }
    }

    /// Creative direction only. Dialogue and character choices always come from the model.
    var instructions: String {
        switch self {
        case .lightChatter:
            "Light chatter: affectionate, low-stakes gossip. Two different mascots speak once each."
        case .loudWhispering:
            "Loud whispering: two mascots, exactly three turns in A-B-A order. Make the gossip meaner: pointed shade, smug disbelief, then a cutting comeback about a fictional mascot's vanity or ridiculous pretensions. Each turn adds something to the same rumour."
        case .egregiousEchoing:
            "Egregious echoing: a merciless fictional mascot roast. Use every candidate if there are at most five; otherwise choose five. Choose a speaking order, then repeat that order for a second pass, so each mascot speaks exactly twice. Build one absurd scandal about an invented, absent app mascot. Let each speaker pile on with a sharper accusation, a withering comparison, or a devastating callback. Make it outrageously catty, theatrical, and viciously funny, with distinct voices. Escalate the same scandal across both passes; end with the sharpest punchline. Avoid consecutive turns by the same mascot."
        }
    }
}

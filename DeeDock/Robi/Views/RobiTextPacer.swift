import Observation
import SwiftUI

/// Reveals a streamed answer at an even pace, with a soft leading edge.
///
/// Models deliver text in bursts: many characters at once, then nothing for a few hundred
/// milliseconds. Shown as it arrives, the answer jumps and stalls. The pacer keeps the arriving
/// text as a target and reveals it word by word at a rate that follows the arrival rate, holding a
/// fifth of a second of text in reserve so a gap between bursts is covered by text already
/// received. The newest words fade in over a quarter second instead of popping in.
///
/// This is presentation only. Copy, Replace and Paste read `RobiModel.answerText`, which always
/// holds the full text. With Reduce Motion the pacer shows the target as it arrives, without fading.
///
/// One pacer belongs to one answer card. It owns a single tick task, which runs while text is
/// waiting or still fading and ends when it catches up; `pause()` cancels it when the answer
/// leaves the screen. Only the properties views draw are observed, so a tick redraws the answer
/// text and nothing else.
@MainActor @Observable
final class RobiTextPacer {
    /// What the pacer is given each time the answer, its completion or Reduce Motion changes.
    struct Input: Equatable {
        /// Everything that has arrived so far. Snapshots are cumulative.
        var target: String
        /// The answer is complete or stopped, so the rest can be shown quickly.
        var isFinished: Bool
        var reduceMotion: Bool
    }

    /// The revealed text. Its last few words carry a lower foreground opacity while they fade in.
    private(set) var text = AttributedString()
    /// At least one character is revealed. Changes only when that flips, so views that switch on
    /// it do not redraw every tick.
    private(set) var hasText = false

    // MARK: Pacing constants

    /// One step of the reveal, about 30 Hz.
    private static let tick: Duration = .milliseconds(30)
    /// How long the first words are held, so the first rate estimate has something to go on.
    private static let initialHold: TimeInterval = 0.14
    /// Enough waiting text to start before `initialHold` has passed.
    private static let initialHoldCharacters = 40
    /// Time constant of the smoothed arrival rate. Long enough to average across bursts.
    private static let arrivalSmoothing: TimeInterval = 0.8
    /// Text kept in reserve, as seconds of the arrival rate. This is the delay that turns bursts
    /// into a steady flow: a gap shorter than this is covered by text already received.
    private static let reserve: TimeInterval = 0.2
    /// How quickly backlog beyond the reserve is worked off, so the reveal never falls far behind.
    private static let catchUp: TimeInterval = 0.4
    /// The slowest reveal while text is waiting, in characters per second.
    private static let minimumRate: Double = 24
    /// How long the rest takes to appear once the answer is complete or stopped.
    private static let flushDuration: TimeInterval = 0.3
    /// How long a word that may still be growing is held at the end of the received text.
    private static let wordWait: TimeInterval = 0.3
    /// Longest run revealed as one word. Long tokens such as URLs are split after this many.
    private static let maxWordLength = 16
    /// Budget carried while waiting for text, so the word after a pause does not wait twice.
    private static let carriedBudget: Double = 6
    /// How long newly revealed text takes to reach full opacity, and where it starts.
    private static let fadeDuration: TimeInterval = 0.24
    private static let fadeFloor: Double = 0.15

    // MARK: State

    /// The target as characters, so reveal positions never split a grapheme such as an emoji.
    @ObservationIgnored private var characters: [Character] = []
    /// Characters revealed so far.
    @ObservationIgnored private var revealed = 0
    /// Characters before this index are fully opaque; the rest of the revealed text is in `fades`.
    @ObservationIgnored private var opaqueEnd = 0
    /// Groups of characters revealed in one tick, oldest first: each ends at `end` and started
    /// fading in at `time`. Fading by time rather than by distance from the end lets the last
    /// words settle while the stream pauses.
    @ObservationIgnored private var fades: [(end: Int, time: TimeInterval)] = []
    /// Fractional characters the reveal may still spend; words are revealed whole.
    @ObservationIgnored private var budget: Double = 0
    /// The smoothed arrival rate, in characters per second, as of `lastArrival`.
    @ObservationIgnored private var arrivalRate: Double = 0
    @ObservationIgnored private var lastArrival: TimeInterval = 0
    @ObservationIgnored private var firstArrival: TimeInterval = 0
    /// The rate that shows the rest within `flushDuration`, set when the answer finishes.
    @ObservationIgnored private var flushRate: Double = 0
    @ObservationIgnored private var isFinished = false
    /// False until the first input. Text present on the first input, such as an answer brought
    /// back from another window, is shown at once rather than replayed.
    @ObservationIgnored private var isSynced = false
    @ObservationIgnored private var lastStep: TimeInterval = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Takes the latest answer. Growth is paced; an empty target clears the text; any other change,
    /// such as a different answer, is shown at once.
    func update(_ input: Input) {
        let now = Self.now()
        let wasFinished = isFinished
        isFinished = input.isFinished
        guard !input.reduceMotion else { return show(input.target) }
        guard !input.target.isEmpty else { return show("") }
        let next = Array(input.target)
        guard isSynced, next.starts(with: characters.prefix(revealed)) else { return show(input.target) }

        let grown = next.count - characters.count
        if grown > 0 {
            if revealed == 0, characters.isEmpty { firstArrival = now }
            arrivalRate = currentArrivalRate(at: now) + Double(grown) / Self.arrivalSmoothing
            lastArrival = now
        }
        characters = next
        if isFinished, !wasFinished || grown > 0 {
            flushRate = Double(characters.count - revealed) / Self.flushDuration
        }
        start()
    }

    /// Stops the tick task, for when the answer leaves the screen. The next `update(_:)` resumes.
    func pause() {
        task?.cancel()
        task = nil
    }

    // MARK: Revealing

    /// Shows `target` in full with nothing fading, and makes it the base for later growth.
    private func show(_ target: String) {
        pause()
        characters = Array(target)
        revealed = characters.count
        opaqueEnd = revealed
        fades = []
        budget = 0
        arrivalRate = 0
        flushRate = 0
        isSynced = true
        text = AttributedString(target)
        if hasText != !target.isEmpty { hasText = !target.isEmpty }
    }

    private func start() {
        guard task == nil, revealed < characters.count || !fades.isEmpty else { return }
        lastStep = Self.now()
        task = Task { [weak self] in
            while true {
                try? await Task.sleep(for: RobiTextPacer.tick)
                // `pause()` already cleared `task`; a replacement may be running.
                guard !Task.isCancelled, let self else { return }
                if !self.step() {
                    self.task = nil
                    return
                }
            }
        }
    }

    /// Advances the reveal and the fades by the time since the last step. Returns whether another
    /// step is needed: text is still waiting, or revealed text is still fading in.
    private func step() -> Bool {
        let now = Self.now()
        // Capped so a stalled main thread does not dump a paragraph at once.
        let elapsed = min(now - lastStep, 0.1)
        lastStep = now
        var changed = false

        let holding = revealed == 0 && !isFinished && now - firstArrival < Self.initialHold
            && characters.count < Self.initialHoldCharacters
        if !holding {
            budget += rate(at: now) * elapsed
            let before = revealed
            var stop = nextStop(after: revealed, at: now)
            while let end = stop, Double(end - revealed) <= budget {
                budget -= Double(end - revealed)
                revealed = end
                stop = nextStop(after: revealed, at: now)
            }
            // Waiting on text rather than on budget: do not save up a burst for when it arrives.
            if stop == nil { budget = min(budget, Self.carriedBudget) }
            if revealed > before {
                fades.append((end: revealed, time: now))
                changed = true
            }
        }

        while let oldest = fades.first, now - oldest.time >= Self.fadeDuration {
            opaqueEnd = oldest.end
            fades.removeFirst()
            changed = true
        }
        if changed || !fades.isEmpty { render(at: now) }
        return revealed < characters.count || !fades.isEmpty
    }

    /// Characters per second: the smoothed arrival rate, adjusted toward keeping `reserve` seconds
    /// of text waiting. Never below `minimumRate`, and at least the flush rate once finished.
    private func rate(at now: TimeInterval) -> Double {
        let arrival = currentArrivalRate(at: now)
        let backlog = Double(characters.count - revealed)
        var rate = max(arrival + (backlog - arrival * Self.reserve) / Self.catchUp, Self.minimumRate)
        if isFinished { rate = max(rate, flushRate) }
        return rate
    }

    /// The arrival rate decayed to `now`: each arrival adds `count / arrivalSmoothing` and fades
    /// exponentially, so a steady stream of R characters per second settles near R.
    private func currentArrivalRate(at now: TimeInterval) -> Double {
        arrivalRate * exp(-(now - lastArrival) / Self.arrivalSmoothing)
    }

    /// Where the next word ends, counting the whitespace before it, so a paragraph break appears
    /// with the word after it rather than as an empty line. Returns nil when no whole word is
    /// waiting: the received text ends inside a word that may still grow. That word is shown once
    /// the answer finishes or nothing has arrived for `wordWait`.
    ///
    /// Each ideograph counts as a word, since Chinese and Japanese text has no spaces, and a run
    /// longer than `maxWordLength` is split.
    private func nextStop(after position: Int, at now: TimeInterval) -> Int? {
        let count = characters.count
        guard position < count else { return nil }
        var index = position
        while index < count, characters[index].isWhitespace { index += 1 }
        let wordStart = index
        if index < count, Self.standsAlone(characters[index]) { return index + 1 }
        while index < count, index - wordStart < Self.maxWordLength,
              !characters[index].isWhitespace, !Self.standsAlone(characters[index]) {
            index += 1
        }
        if index == count, index - wordStart < Self.maxWordLength,
           !isFinished, now - lastArrival < Self.wordWait {
            return nil
        }
        return index
    }

    private static func standsAlone(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.isIdeographic == true
    }

    /// Rebuilds `text`: the opaque part as is, then each fading group with its own opacity. A few
    /// thousand characters at 30 Hz is cheap next to laying the text out.
    private func render(at now: TimeInterval) {
        var result = AttributedString(String(characters[..<opaqueEnd]))
        var groupStart = opaqueEnd
        for fade in fades {
            var group = AttributedString(String(characters[groupStart..<fade.end]))
            let progress = min(max((now - fade.time) / Self.fadeDuration, 0), 1)
            // Ease-out, so a word is legible early and settles gently.
            let eased = 1 - (1 - progress) * (1 - progress)
            group.foregroundColor = Color.primary.opacity(Self.fadeFloor + (1 - Self.fadeFloor) * eased)
            result.append(group)
            groupStart = fade.end
        }
        text = result
        if hasText != (revealed > 0) { hasText = revealed > 0 }
    }

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

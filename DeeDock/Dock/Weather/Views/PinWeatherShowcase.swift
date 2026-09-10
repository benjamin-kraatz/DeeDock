import SwiftUI

/// The Icon Rust page header: a small dock of sample pins aging in a time-lapse, with the switch.
///
/// Each sample runs through the real ``PinWeatherIntensity`` curve at the current threshold, so
/// what the preview shows is what the dock will draw. Samples start at staggered ages, rust as
/// the time-lapse runs, and come back clean when they reach the end of the timeline or when
/// clicked — the same way using a real pin restores it.
///
/// The surface is deliberately dark in both appearances: rust reads as warm light on metal,
/// which a pale card washes out.
struct PinWeatherShowcase: View {
    let enabled: Bool
    /// Unreadable storage: the switch is locked and the samples stay clean.
    let frozen: Bool
    let unusedDays: Int
    let setEnabled: (Bool) -> Void

    @State private var specimens = PinWeatherSpecimen.shelf
    /// `nil` until the viewer chooses, so the default can follow Reduce Motion.
    @State private var playbackChoice: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { enabled && !frozen }
    private var playing: Bool { active && (playbackChoice ?? !reduceMotion) }

    private func intensity(_ specimen: PinWeatherSpecimen) -> Double {
        // A fixed reference instant keeps the preview independent of the wall clock.
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let unused = specimen.age * Double(unusedDays) * PinWeatherLimits.secondsPerDay
        return PinWeatherIntensity.value(lastUsed: now.addingTimeInterval(-unused),
                                         unusedDays: unusedDays, enabled: active, now: now)
    }

    /// Mean rust across the shelf, which sets how warmly the backdrop glows.
    private var glow: Double {
        specimens.map(intensity).reduce(0, +) / Double(specimens.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
            shelf
                .padding(.top, 26)
                .frame(maxWidth: .infinity)
            PinWeatherTimeline(unusedDays: unusedDays, specimens: specimens)
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .opacity(active ? 1 : 0.35)
            footer
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 14)
        }
        .background { PinWeatherShowcaseBackdrop(glow: glow) }
        .clipShape(.rect(cornerRadius: SettingsMetrics.cardRadius + 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius + 4, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.4), value: active)
        .task(id: playing) { await runTimeLapse() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(.pinWeatherEnabled)
                    .font(.title3.weight(.semibold))
                Text(.pinWeatherEnabledHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { enabled }, set: setEnabled)) { Text(.pinWeatherEnabled) }
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(frozen)
        }
    }

    private var shelf: some View {
        HStack(spacing: 14) {
            ForEach(specimens) { specimen in
                PinWeatherSpecimenButton(specimen: specimen, intensity: intensity(specimen),
                                         unusedDays: unusedDays) { use(specimen.id) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            // A glass dock shelf: a faint fill and a brighter top edge, like the real Dock.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        }
        .disabled(!active)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.pinWeatherPreviewTitle))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(.pinWeatherPreviewHelp)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                playbackChoice = !playing
            } label: {
                Label(playing ? .pinWeatherHeroPause : .pinWeatherHeroPlay,
                      systemImage: playing ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!active)
            .help(Text(playing ? .pinWeatherHeroPause : .pinWeatherHeroPlay))
        }
        .font(.caption)
        .opacity(active ? 1 : 0.5)
    }

    private func use(_ id: PinWeatherSpecimen.ID) {
        guard let index = specimens.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
            specimens[index].age = 0
            specimens[index].restores += 1
        }
    }

    /// Ages every sample at ten steps a second. Owned by `.task(id:)`, so pausing, turning
    /// the feature off, or leaving the page cancels it.
    private func runTimeLapse() async {
        guard playing else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            withAnimation(.linear(duration: 0.1)) {
                for index in specimens.indices where specimens[index].age < PinWeatherSpecimen.maximumAge {
                    specimens[index].age += PinWeatherSpecimen.agePerStep
                }
            }
            // A sample at the far end is "used" again, so the shelf keeps a mix of ages.
            for specimen in specimens where specimen.age >= PinWeatherSpecimen.maximumAge {
                use(specimen.id)
            }
        }
    }
}

/// One sample pin in the showcase. Its age is in threshold units, so the preview keeps its
/// rhythm whatever the unused-day setting is.
struct PinWeatherSpecimen: Identifiable, Equatable {
    let id: Int
    let symbol: String
    let colors: [Color]
    /// Unused time as a multiple of the threshold: `1` is the first rust, `2` is fully rusted.
    var age: Double
    /// Bumped each time the sample is used, to replay its polish.
    var restores = 0

    /// The end of the timeline. Slightly past full rust so a rusted pin lingers before renewal.
    static let maximumAge = 2.4
    /// One time-lapse step: a sample crosses the whole timeline in about twelve seconds.
    static let agePerStep = maximumAge / 120

    /// Stand-in artwork with staggered ages, so a still frame already shows every stage.
    /// Gradients and symbols instead of real app icons keep Settings off Launch Services.
    static let shelf: [PinWeatherSpecimen] = [
        .init(id: 0, symbol: "safari.fill", colors: [.init(red: 0.30, green: 0.70, blue: 1.00), .init(red: 0.05, green: 0.36, blue: 0.86)], age: 0.25),
        .init(id: 1, symbol: "envelope.fill", colors: [.init(red: 0.40, green: 0.78, blue: 1.00), .init(red: 0.12, green: 0.50, blue: 0.95)], age: 1.9),
        .init(id: 2, symbol: "music.note", colors: [.init(red: 1.00, green: 0.42, blue: 0.52), .init(red: 0.92, green: 0.16, blue: 0.30)], age: 0.8),
        .init(id: 3, symbol: "message.fill", colors: [.init(red: 0.42, green: 0.90, blue: 0.46), .init(red: 0.12, green: 0.70, blue: 0.26)], age: 1.35),
        .init(id: 4, symbol: "folder.fill", colors: [.init(red: 0.52, green: 0.80, blue: 0.98), .init(red: 0.24, green: 0.58, blue: 0.90)], age: 2.2)
    ]
}

/// The showcase's ground: dark graphite with a rust-colored glow that warms as the shelf ages.
private struct PinWeatherShowcaseBackdrop: View {
    /// Mean rust, `0...1`.
    let glow: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.15, green: 0.14, blue: 0.14),
                                    Color(red: 0.07, green: 0.065, blue: 0.065)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.85, green: 0.36, blue: 0.12).opacity(0.10 + 0.55 * glow),
                                    Color(red: 0.55, green: 0.18, blue: 0.06).opacity(0.25 * glow),
                                    .clear],
                           center: UnitPoint(x: 0.5, y: 0.48), startRadius: 0, endRadius: 330)
                .animation(.easeInOut(duration: 0.8), value: glow)
            PinWeatherGrain()
                .blendMode(.overlay)
                .opacity(0.6)
        }
        .accessibilityHidden(true)
    }
}

/// A fine, fixed film grain that gives the backdrop a cast-metal feel.
private struct PinWeatherGrain: View {
    /// Unit-space grain positions and tones, generated once so the texture never shimmers.
    private static let grains: [(x: Double, y: Double, light: Bool, alpha: Double)] = {
        var state: UInt64 = 0xC0FF_EE0D_D0C4_0051
        func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) * 0x1p-53
        }
        return (0..<1_400).map { _ in (next(), next(), next() > 0.5, 0.08 + 0.22 * next()) }
    }()

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            for grain in Self.grains {
                let rect = CGRect(x: grain.x * size.width, y: grain.y * size.height, width: 1, height: 1)
                context.fill(Path(rect), with: .color((grain.light ? Color.white : .black).opacity(grain.alpha)))
            }
        }
    }
}

#if DEBUG
#Preview("Showcase") {
    @Previewable @State var enabled = true
    @Previewable @State var days = 30
    PinWeatherShowcase(enabled: enabled, frozen: false, unusedDays: days, setEnabled: { enabled = $0 })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Showcase off, light") {
    PinWeatherShowcase(enabled: false, frozen: false, unusedDays: 30, setEnabled: { _ in })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.light)
}
#endif

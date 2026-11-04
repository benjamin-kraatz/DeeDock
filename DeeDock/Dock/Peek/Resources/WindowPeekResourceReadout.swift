import SwiftUI

/// The live CPU, memory, and network figures under a Window Peek title. Current numbers, no chart.
///
/// Each figure is a small SF Symbol followed by its value, so processor, memory, and the two
/// network directions stay distinct by shape rather than color. The row grows as figures arrive:
/// memory alone first, CPU after the second sample, and network only when its interface works.
/// A panel too narrow for one row moves network to a second line instead of truncating a unit.
///
/// VoiceOver hears one element, "Current use", whose value names each figure in words.
struct WindowPeekResourceReadout: View {
    let reading: WindowPeekResourceReading
    @Environment(\.locale) private var locale

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                processorAndMemory
                network
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) { processorAndMemory }
                network
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.windowPeekResourcesAccessibilityLabel))
        .accessibilityValue(Text(verbatim: WindowPeekResourceText.spoken(reading, locale: locale)))
    }

    @ViewBuilder private var processorAndMemory: some View {
        if let cpuPercent = reading.cpuPercent {
            WindowPeekResourceFigure(symbol: "cpu", value: WindowPeekResourceText.percent(cpuPercent, locale: locale),
                                     help: WindowPeekResourceText.spokenCPU(reading, locale: locale))
        }
        WindowPeekResourceFigure(symbol: "memorychip", value: WindowPeekResourceText.memory(reading.memoryBytes, locale: locale),
                                 help: WindowPeekResourceText.spokenMemory(reading, locale: locale))
    }

    @ViewBuilder private var network: some View {
        if let rate = reading.network {
            let help = WindowPeekResourceText.spokenNetwork(reading, locale: locale)
            HStack(spacing: 8) {
                WindowPeekResourceFigure(symbol: "arrow.down",
                                         value: WindowPeekResourceText.rate(rate.receivedPerSecond, locale: locale),
                                         help: help)
                WindowPeekResourceFigure(symbol: "arrow.up",
                                         value: WindowPeekResourceText.rate(rate.sentPerSecond, locale: locale),
                                         help: help)
            }
        }
    }
}

/// One glyph-and-number pair in the readout. The glyph is decoration; the parent speaks for it.
private struct WindowPeekResourceFigure: View {
    let symbol: String
    let value: String
    let help: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.tertiary)
            Text(verbatim: value)
                .monospacedDigit()
        }
        .lineLimit(1)
        // A figure never shrinks into an ellipsis; ViewThatFits moves it to a new line instead.
        .fixedSize()
        .help(help ?? "")
    }
}

#if DEBUG
private let windowPeekResourcePreviewMemoryOnly = WindowPeekResourceReading(cpuPercent: nil, memoryBytes: 842_000_000)
private let windowPeekResourcePreviewCompute = WindowPeekResourceReading(cpuPercent: 9, memoryBytes: 4_470_000_000)
private let windowPeekResourcePreviewFull = WindowPeekResourceReading(
    cpuPercent: 9, memoryBytes: 4_470_000_000,
    network: WindowPeekNetworkRate(receivedPerSecond: 152, sentPerSecond: 286))
private let windowPeekResourcePreviewBusy = WindowPeekResourceReading(
    cpuPercent: 142, memoryBytes: 12_340_000_000,
    network: WindowPeekNetworkRate(receivedPerSecond: 987_600, sentPerSecond: 48_300_000))

/// Every readout state at a card width, in one locale.
private struct WindowPeekResourceReadoutPreviewStack: View {
    var width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WindowPeekResourceReadout(reading: windowPeekResourcePreviewMemoryOnly)
            WindowPeekResourceReadout(reading: windowPeekResourcePreviewCompute)
            WindowPeekResourceReadout(reading: windowPeekResourcePreviewFull)
            WindowPeekResourceReadout(reading: windowPeekResourcePreviewBusy)
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding()
    }
}

#Preview("States") {
    WindowPeekResourceReadoutPreviewStack()
}

#Preview("States, German") {
    WindowPeekResourceReadoutPreviewStack()
        .environment(\.locale, Locale(identifier: "de_DE"))
}

#Preview("Narrow card, German") {
    WindowPeekResourceReadoutPreviewStack(width: 210)
        .environment(\.locale, Locale(identifier: "de_DE"))
}
#endif

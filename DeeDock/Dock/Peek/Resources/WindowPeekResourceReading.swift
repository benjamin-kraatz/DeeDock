import Foundation

/// One glance at the app Window Peek is showing: current processor use, memory, and network, with no history.
///
/// CPU is the same scale Activity Monitor and App Health use, where 100 is one core fully busy.
/// It stays nil on the baseline sample, which only records counters. Memory is the summed physical
/// footprint of the app and the helpers attribution can see, and is valid on the first sample.
/// Network is nil until a second sample, and nil when the private interface is unavailable.
nonisolated struct WindowPeekResourceReading: Equatable, Sendable {
    var cpuPercent: Double?
    /// Physical footprint, in bytes.
    var memoryBytes: UInt64
    var network: WindowPeekNetworkRate?

    /// Nil when `usage` names no process, so a quit app does not keep showing its last numbers.
    init?(usage: AppHealthAppUsage, interval: Double?, network: WindowPeekNetworkRate? = nil) {
        guard usage.procs > 0 else { return nil }
        memoryBytes = usage.mem
        cpuPercent = if let interval, interval > 0 { usage.cpu / interval * 100 } else { nil }
        self.network = network
    }

    init(cpuPercent: Double?, memoryBytes: UInt64, network: WindowPeekNetworkRate? = nil) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.network = network
    }
}

/// Locale-aware strings for a `WindowPeekResourceReading`: short visible figures, and the
/// spoken sentence VoiceOver reads instead of the icons.
///
/// Every function takes the locale from the SwiftUI environment, so a preview in German shows
/// German separators even on an English Mac.
enum WindowPeekResourceText {
    /// Whole percent, so a quiet app reads "0 %" and a busy one "140 %".
    static func percent(_ cpuPercent: Double, locale: Locale = .current) -> String {
        (cpuPercent / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Physical footprint in the binary units Activity Monitor uses, such as "1.4 GB".
    static func memory(_ bytes: UInt64, locale: Locale = .current) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .memory).locale(locale))
    }

    /// A throughput amount without the per-second suffix, such as "1.2 MB".
    ///
    /// Never smaller than kilobytes: a trickle of 152 bytes reads "< 1 kB", and silence "0 kB",
    /// so the unit stays the same width as the other figures instead of spelling out "bytes".
    static func amount(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        let bytes = Int64(exactly: max(0, bytesPerSecond).rounded()) ?? Int64.max
        guard bytes >= 1_000 else {
            let style = Measurement<UnitInformationStorage>.FormatStyle(width: .abbreviated, locale: locale,
                                                                          usage: .asProvided)
            guard bytes > 0 else { return Measurement(value: 0, unit: UnitInformationStorage.kilobytes).formatted(style) }
            let one = Measurement(value: 1, unit: UnitInformationStorage.kilobytes).formatted(style)
            return resolve(.windowPeekResourcesBelowAmount(amount: one), locale)
        }
        return bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// A visible rate such as "1.2 MB/s".
    static func rate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        resolve(.windowPeekResourcesRate(amount: amount(bytesPerSecond, locale: locale)), locale)
    }

    /// What VoiceOver reads, such as "CPU 14 %, memory 1.4 GB, receiving 1 MB per second,
    /// sending 200 kB per second". Each figure is named in words, because the screen only shows icons.
    static func spoken(_ reading: WindowPeekResourceReading, locale: Locale = .current) -> String {
        [spokenCPU(reading, locale: locale), spokenMemory(reading, locale: locale),
         spokenNetwork(reading, locale: locale)]
            .compactMap(\.self)
            .formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// "CPU 14 %", or nil before a second sample exists.
    static func spokenCPU(_ reading: WindowPeekResourceReading, locale: Locale = .current) -> String? {
        reading.cpuPercent.map {
            resolve(.windowPeekResourcesSpokenCPU(cpu: percent($0, locale: locale)), locale)
        }
    }

    /// "Memory 1.4 GB". Memory is valid from the first sample.
    static func spokenMemory(_ reading: WindowPeekResourceReading, locale: Locale = .current) -> String {
        resolve(.windowPeekResourcesSpokenMemory(memory: memory(reading.memoryBytes, locale: locale)), locale)
    }

    /// "Receiving 1 MB per second, sending 200 kB per second", or nil without a network rate.
    static func spokenNetwork(_ reading: WindowPeekResourceReading, locale: Locale = .current) -> String? {
        reading.network.map {
            resolve(.windowPeekResourcesSpokenNetwork(down: amount($0.receivedPerSecond, locale: locale),
                                                       up: amount($0.sentPerSecond, locale: locale)), locale)
        }
    }

    private static func resolve(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}

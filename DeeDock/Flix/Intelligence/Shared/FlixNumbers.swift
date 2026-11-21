import Foundation

/// Safe conversions for numbers Flix Files did not produce itself: values parsed from window text,
/// OCR, file contents, metadata, and model output.
///
/// `Int(_:)` and `Int64(_:)` trap on NaN, infinity, and anything outside their range, and such a
/// value is one long digit string or one odd model answer away. Every conversion of an untrusted
/// `Double` goes through here: non-finite values and values outside the caller's bounds come back
/// as nil, so the caller treats them as "no number".
nonisolated enum FlixNumbers {
    /// The largest amount of money Flix Files keeps as a fact or a search bound. Far above any
    /// invoice, far below where `Double` loses whole units.
    static let maximumAmount: Double = 1_000_000_000_000

    /// `value` when it is finite and within `range`, else nil.
    static func finite(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    /// A positive, finite amount of money no larger than ``maximumAmount``, else nil.
    static func amount(_ value: Double?) -> Double? {
        guard let value = finite(value, in: 0...maximumAmount), value > 0 else { return nil }
        return value
    }

    /// `value` rounded toward zero as an `Int64`, or nil when it is not finite or the result lies
    /// outside `range`.
    static func int64(_ value: Double, in range: ClosedRange<Int64>) -> Int64? {
        guard value.isFinite else { return nil }
        let truncated = value.rounded(.towardZero)
        // Compare as Doubles first: converting an out-of-range Double is what traps.
        guard truncated >= Double(range.lowerBound), truncated <= Double(range.upperBound),
              let result = Int64(exactly: truncated) else { return nil }
        return range.contains(result) ? result : nil
    }

    /// `value` rounded toward zero as an `Int`, or nil when it is not finite or the result lies
    /// outside `range`.
    static func int(_ value: Double, in range: ClosedRange<Int>) -> Int? {
        int64(value, in: Int64(range.lowerBound)...Int64(range.upperBound)).map { Int($0) }
    }
}

import Foundation

/// A DOKK version number that may leave the device as an analytics property value.
///
/// Update events need the running version and the offered one, and both are text. Only text
/// made of one to four dot-separated numbers is accepted, such as `0.13.5`, so nothing but a
/// version number can pass through this type. Anything else, including a pre-release suffix,
/// becomes nil and the property is left out.
nonisolated struct AnalyticsVersion: Equatable, Sendable {
    let text: String

    /// - Parameter text: A marketing version such as `CFBundleShortVersionString` or Sparkle's
    ///   display version. Nil, empty, or any other shape yields nil.
    init?(_ text: String?) {
        guard let text, text.count <= 32 else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        self.text = text
    }

    /// A build number such as `CFBundleVersion` or Sparkle's version string. DOKK builds are
    /// whole numbers; anything else is not reported.
    static func build(_ text: String?) -> Int? {
        guard let text, text.count <= 18, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

import Foundation

/// Marks an enum whose raw values may leave the device as analytics property values.
///
/// Conform only enums whose cases are compile-time constants. A type that wraps arbitrary text,
/// such as an app name or a path, must never conform: this protocol, ``AnalyticsFileType``, and
/// ``AnalyticsVersion`` are the only ways text becomes an ``AnalyticsValue``.
nonisolated protocol AnalyticsToken: RawRepresentable where RawValue == String {}

/// One analytics property value: a Bool, an exact number, or an enum token.
///
/// There is deliberately no initializer that takes a `String`, so an app name, bundle ID, path,
/// window title, or query cannot be passed to an event by mistake. The compiler rejects it.
nonisolated struct AnalyticsValue: Equatable, Sendable {
    fileprivate enum Storage: Equatable, Sendable {
        case bool(Bool), int(Int), double(Double), token(String)
    }

    fileprivate let storage: Storage

    init(_ value: Bool) { storage = .bool(value) }
    init(_ value: Int) { storage = .int(value) }
    /// Non-finite numbers have no JSON form; they are sent as zero.
    init(_ value: Double) { storage = .double(value.isFinite ? value : 0) }
    init<Token: AnalyticsToken>(_ token: Token) { storage = .token(token.rawValue) }
    init(_ fileType: AnalyticsFileType) { storage = .token(fileType.identifier) }
    init(_ version: AnalyticsVersion) { storage = .token(version.text) }
    fileprivate init(token: String) { storage = .token(token) }

    /// The JSON-compatible form handed to the backend.
    var payload: Any {
        switch storage {
        case let .bool(value): value
        case let .int(value): value
        case let .double(value): value
        case let .token(value): value
        }
    }

    /// Developer-facing rendering for the "recently sent" list in Settings.
    var displayText: String {
        switch storage {
        case let .bool(value): value ? "true" : "false"
        case let .int(value): String(value)
        case let .double(value): String(value)
        case let .token(value): value
        }
    }
}

/// Properties of one event. Keys written in source must be string literals.
///
/// Keys produced by ``init(reflecting:prefix:)`` come from Swift property names, which are
/// compile-time identifiers as well.
nonisolated struct AnalyticsProperties: Equatable, Sendable, ExpressibleByDictionaryLiteral {
    private(set) var values: [String: AnalyticsValue] = [:]

    init() {}

    /// A nil value omits its key, so optional measurements need no branching at the call site.
    init(dictionaryLiteral elements: (StaticString, AnalyticsValue?)...) {
        for (key, value) in elements { values["\(key)"] = value }
    }

    /// Counter totals keyed by ``AnalyticsCounter/key``. Only the counter store calls this.
    init(counterTotals: [String: Int]) {
        values = counterTotals.mapValues(AnalyticsValue.init)
    }

    var isEmpty: Bool { values.isEmpty }

    /// The JSON-compatible form handed to the backend.
    var payload: [String: Any] { values.mapValues(\.payload) }

    subscript(key: StaticString) -> AnalyticsValue? {
        get { values["\(key)"] }
        set { values["\(key)"] = newValue }
    }

    /// Adds `other`, which wins on a shared key.
    mutating func merge(_ other: AnalyticsProperties) {
        values.merge(other.values) { _, new in new }
    }

    func merging(_ other: AnalyticsProperties) -> AnalyticsProperties {
        var result = self
        result.merge(other)
        return result
    }

    /// Keys present in `self` and absent from `other`.
    func keys(missingFrom other: AnalyticsProperties) -> [String] {
        values.keys.filter { other.values[$0] == nil }
    }

    /// The entries of `self` that `other` lacks or holds with a different value.
    func changes(from other: AnalyticsProperties) -> AnalyticsProperties {
        var result = AnalyticsProperties()
        result.values = values.filter { other.values[$0.key] != $0.value }
        return result
    }
}

// MARK: - Scopes

/// Which part of DOKK a group of properties describes. It becomes a key prefix, so the same
/// setting can be reported for the shared defaults and for each display.
///
/// Displays are identified by role and position only, never by name or serial number.
nonisolated enum AnalyticsScope: Sendable {
    case none
    case named(StaticString)
    /// A display other than the main one, numbered from 1 in left-to-right arrangement order.
    case secondaryDisplay(Int)

    /// The shared dock defaults every display inherits.
    static let shared = AnalyticsScope.named("shared")
    static let mainDisplay = AnalyticsScope.named("main")

    fileprivate var prefix: String {
        switch self {
        case .none: ""
        case let .named(name): "\(name)_"
        case let .secondaryDisplay(index): "secondary_\(index)_"
        }
    }
}

// MARK: - Reflection

extension AnalyticsProperties {
    /// Flattens a settings model into properties without naming its fields in analytics code,
    /// so a setting added to the model is reported without touching this file.
    ///
    /// Only values that cannot carry user content are emitted:
    /// - `Bool` and numbers are sent as they are.
    /// - Enum cases are sent by name. Associated values are dropped.
    /// - Text, URLs, dates, identifiers, and data are reduced to `<key>_set`, a Bool. Their
    ///   contents never leave the device. This covers path settings such as the markup folder.
    /// - Collections are reduced to `<key>_count`.
    /// - Nested structs are flattened with their property name as a key prefix.
    ///
    /// Keys are the model's property names in snake case, after the scope's prefix.
    init(reflecting model: Any, scope: AnalyticsScope = .none) {
        Self.flatten(model, key: "", into: &values)
        self = scoped(scope)
    }

    /// The same properties with the scope's prefix on every key.
    func scoped(_ scope: AnalyticsScope) -> AnalyticsProperties {
        let prefix = scope.prefix
        guard !prefix.isEmpty else { return self }
        var result = AnalyticsProperties()
        for (key, value) in values { result.values[prefix + key] = value }
        return result
    }

    private static func flatten(_ value: Any, key: String, into values: inout [String: AnalyticsValue]) {
        if let optional = value as? any AnalyticsOptional {
            guard let wrapped = optional.analyticsWrapped else {
                if optional.wrapsOpaqueValue { values[key + "_set"] = AnalyticsValue(false) }
                return
            }
            return flatten(wrapped, key: key, into: &values)
        }
        switch value {
        case let value as Bool: values[key] = AnalyticsValue(value)
        case let value as Int: values[key] = AnalyticsValue(value)
        case let value as Double: values[key] = AnalyticsValue(value)
        case let value as CGFloat: values[key] = AnalyticsValue(Double(value))
        case let value as Float: values[key] = AnalyticsValue(Double(value))
        case is String, is URL, is Data, is Date, is UUID: values[key + "_set"] = AnalyticsValue(true)
        default:
            let mirror = Mirror(reflecting: value)
            switch mirror.displayStyle {
            case .enum:
                if let name = caseName(of: value, mirror: mirror) { values[key] = AnalyticsValue(token: name) }
            case .struct, .tuple:
                for child in mirror.children {
                    guard let label = child.label else { continue }
                    flatten(child.value, key: key.isEmpty ? snakeCase(label) : key + "_" + snakeCase(label), into: &values)
                }
            case .collection, .set, .dictionary:
                values[key + "_count"] = AnalyticsValue(mirror.children.count)
            default:
                break
            }
        }
    }

    /// The case name of an enum value, which is a compile-time identifier.
    ///
    /// A payload-free case of an enum without raw values has no reflected label, so its
    /// description is used, but only when the type does not customize that description.
    private static func caseName(of value: Any, mirror: Mirror) -> String? {
        if let raw = (value as? any RawRepresentable)?.rawValue {
            if let raw = raw as? String { return raw }
            if let raw = raw as? Int { return String(raw) }
            return nil
        }
        if let label = mirror.children.first?.label { return label }
        guard !(value is any CustomStringConvertible), !(value is any CustomDebugStringConvertible) else { return nil }
        return String(describing: value)
    }

    private static func snakeCase(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase {
                if !result.isEmpty { result.append("_") }
                result.append(contentsOf: character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }
}

/// Lets reflection see through `Optional` and tell an unset text field from an unset number.
private protocol AnalyticsOptional {
    var analyticsWrapped: Any? { get }
    var wrapsOpaqueValue: Bool { get }
}

extension Optional: AnalyticsOptional {
    fileprivate nonisolated var analyticsWrapped: Any? { self }
    fileprivate nonisolated var wrapsOpaqueValue: Bool {
        Wrapped.self == String.self || Wrapped.self == URL.self || Wrapped.self == Data.self
    }
}

// MARK: - Setting changes

/// One changed setting, produced only by comparing two versions of a settings model.
nonisolated struct AnalyticsSettingChange: Equatable, Sendable {
    /// The reflected property name, such as `icon_size` or `behavior_auto_hide`.
    fileprivate let key: String
    /// Absent when the setting had no reportable value before, such as an unset optional.
    let oldValue: AnalyticsValue?
    let newValue: AnalyticsValue?

    /// Identifies the setting when consecutive edits are folded into one event.
    var identity: String { key }

    var properties: AnalyticsProperties {
        ["key": AnalyticsValue(token: key), "old_value": oldValue, "new_value": newValue]
    }

    /// Keeps the first old value across a run of edits, such as a slider drag.
    func following(_ earlier: AnalyticsSettingChange) -> AnalyticsSettingChange {
        AnalyticsSettingChange(key: key, oldValue: earlier.oldValue, newValue: newValue)
    }

    /// Every setting whose reported value differs between two versions of the same model.
    static func changes(from old: Any, to new: Any) -> [AnalyticsSettingChange] {
        let before = AnalyticsProperties(reflecting: old).values
        let after = AnalyticsProperties(reflecting: new).values
        return Set(before.keys).union(after.keys).sorted().compactMap { key in
            before[key] == after[key] ? nil
                : AnalyticsSettingChange(key: key, oldValue: before[key], newValue: after[key])
        }
    }
}

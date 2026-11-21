import Foundation

/// Phase B1's drag hooks: converted copies for windows with type or size limits, and the sensitive
/// file question for outside targets.
///
/// Both answer synchronously from work already done — conversions ``FlixConversionStore`` prepared,
/// verdicts ``FlixSensitiveGuard`` cached — because they run at drag start. A conversion that is not
/// ready yet leaves the original on the pasteboard; that drag goes out unchanged.
@MainActor
final class FlixDragInterceptor: FlixDragIntercepting {
    private let conversions: FlixConversionStore
    private let sensitive: FlixSensitiveGuard
    /// The demand of the window a context names, from the Fits cache.
    var demand: (FlixFrontmostContext?) -> FlixWindowDemand? = { _ in nil }
    /// The window's name for the question ("portal.example.com"), else the app's.
    var destinationLabel: (FlixFrontmostContext?) -> String? = { $0?.applicationName }
    var settings: () -> FlixSettings = { FlixSettings() }

    init(conversions: FlixConversionStore, sensitive: FlixSensitiveGuard) {
        self.conversions = conversions
        self.sensitive = sensitive
    }

    // MARK: FlixDragIntercepting

    func plan(for items: [FlixItem], context: FlixFrontmostContext?, fits: FlixFitsResult?) -> FlixDragPlan? {
        guard let demand = demand(context), demand.hasLimits else { return nil }
        var plan = FlixDragPlan()
        var prepared: [FlixPreparedConversion] = []
        for item in items {
            guard let conversion = conversion(for: item, demand: demand) else { continue }
            plan.substitutions[item.id] = conversion.url
            prepared.append(conversion)
        }
        guard !prepared.isEmpty else { return nil }
        plan.label = Self.label(for: prepared)
        plan.convertMs = prepared.map(\.durationMs).max()
        return plan
    }

    func confirmation(for items: [FlixItem], context: FlixFrontmostContext?) -> FlixDropConfirmation? {
        guard settings().guardsSensitiveFiles, FlixAppCategory.of(context).isOutside,
              let item = items.first(where: { sensitive.verdict(for: $0) != nil }) else { return nil }
        // The dialog says what kind of file it is; the reason would repeat it.
        return .sensitive(itemID: item.id, reason: nil, destination: destinationLabel(context))
    }

    // MARK: For the Fits rows

    /// "as PDF · 1.2 MB" for a Fits row whose item will be converted, once its copy is ready.
    func chip(for item: FlixItem, context: FlixFrontmostContext?) -> String? {
        guard let demand = demand(context), let conversion = conversion(for: item, demand: demand) else { return nil }
        return String(localized: .flixConvertChip(conversion.recipe.format.displayName, Self.size(conversion.bytes)))
    }

    private func conversion(for item: FlixItem, demand: FlixWindowDemand) -> FlixPreparedConversion? {
        guard case .convert(let recipe) = FlixConversionPlanner.decision(for: item, demand: demand) else { return nil }
        return conversions.prepared(for: item, recipe: recipe)
    }

    // MARK: Labels

    /// The drag picture's label: "✦ Upload as PDF · 1.2 MB", "✦ Upload as PDF · 2 converted",
    /// "✦ Upload smaller · 4.1 MB", or "✦ 3 converted for upload".
    static func label(for conversions: [FlixPreparedConversion]) -> String? {
        guard let first = conversions.first else { return nil }
        if conversions.count == 1 {
            return first.recipe.isResizeOnly
                ? String(localized: .flixConvertLabelResized(size(first.bytes)))
                : String(localized: .flixConvertLabel(first.recipe.format.displayName, size(first.bytes)))
        }
        let formats = Set(conversions.map(\.recipe.format))
        if formats.count == 1, !conversions.contains(where: \.recipe.isResizeOnly) {
            return String(localized: .flixConvertLabelCount(first.recipe.format.displayName, conversions.count))
        }
        return String(localized: .flixConvertLabelMixed(conversions.count))
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

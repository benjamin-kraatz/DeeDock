import AppKit
import ObjectiveC

/// DOKK calls itself BIG DIKK for the week around a few dates.
///
/// The week is the date and the three days on either side, on the Mac's local Gregorian
/// calendar. The choice is fixed at the first lookup, so a launch does not rename itself
/// at midnight. Catalog strings, the in-memory bundle display name, and the application
/// menu pick up the alias. The on-disk app file stays `DOKK.app`; signing and the installed
/// path depend on that name.
nonisolated enum ProductAlias {
    /// The name in the catalog, the built Info.plist, and the app file.
    static let canonical = "DOKK"
    /// Shown in place of ``canonical`` during an alias week.
    static let festive = "BIG DIKK"

    /// A day that repeats every Gregorian year.
    nonisolated struct Occasion: Sendable, Equatable {
        var month: Int
        var day: Int
    }

    /// 14 February, 21 July, 22 August, and 14 November.
    static let occasions = [
        Occasion(month: 2, day: 14),
        Occasion(month: 7, day: 21),
        Occasion(month: 8, day: 22),
        Occasion(month: 11, day: 14),
    ]

    /// Inclusive distance from an occasion. Three days before, the day, and three days after.
    static let radius = 3

    /// Info.plist keys AppKit shows as the app's name. The bundle identifier and analytics
    /// keys stay as built.
    static let displayedBundleNameKeys = ["CFBundleName", "CFBundleDisplayName"]

    /// True when `date` falls in an alias week. `calendar` must be Gregorian; month numbers
    /// are Gregorian months. The check uses whole local days, so a time zone can move an
    /// instant onto the neighboring date.
    static func isActive(on date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        for occasion in occasions {
            for offset in -1...1 {
                guard let occasionDay = calendar.date(from: DateComponents(
                    year: year + offset, month: occasion.month, day: occasion.day)) else { continue }
                let start = calendar.startOfDay(for: occasionDay)
                guard let windowStart = calendar.date(byAdding: .day, value: -radius, to: start),
                      let windowEnd = calendar.date(byAdding: .day, value: radius + 1, to: start) else { continue }
                if day >= windowStart && day < windowEnd { return true }
            }
        }
        return false
    }

    /// Replaces ``canonical`` when `date` is inside an alias week. Other text, including
    /// `DeeDock`, is left as it is.
    static func applying(to text: String, on date: Date, calendar: Calendar) -> String {
        guard isActive(on: date, calendar: calendar) else { return text }
        return replacing(in: text)
    }

    /// The launch decision. Later lookups in this process use the same answer.
    static let presentsFestiveName = isActive(on: Date(), calendar: localGregorian())

    /// ``applying(to:on:calendar:)`` for the name this launch is using.
    static func applying(to text: String) -> String {
        presentsFestiveName ? replacing(in: text) : text
    }

    /// Copies `info` with the displayed bundle names renamed. Other keys, including ones
    /// whose names contain `DOKK`, are unchanged. Returns `info` itself when nothing changes.
    static func renamingDisplayedNames(in info: [String: Any]?, active: Bool) -> [String: Any]? {
        guard let info, active else { return info }
        var copy = info
        var changed = false
        for key in displayedBundleNameKeys {
            guard let text = copy[key] as? String else { continue }
            let renamed = replacing(in: text)
            if renamed != text {
                copy[key] = renamed
                changed = true
            }
        }
        return changed ? copy : info
    }

    /// Points `Bundle.main` at ``ProductAliasBundle`` for this launch when the alias is on.
    ///
    /// The subclass adds no stored properties: `object_setClass` reuses the existing
    /// `NSBundle` instance, so an extra ivar would be out of bounds. Call this before
    /// `App.main()` so AppKit reads the aliased name while it builds the menu. Test hosts
    /// skip it; their localized strings must not depend on the wall clock.
    static func install() {
        guard presentsFestiveName else { return }
        ProcessInfo.processInfo.processName = festive
        guard object_getClass(Bundle.main) != ProductAliasBundle.self else { return }
        object_setClass(Bundle.main, ProductAliasBundle.self)
    }

    /// Writes the alias into the application menu. SwiftUI may rebuild those items, so
    /// the delegate calls this again whenever the app becomes active.
    @MainActor
    static func applyRunningApplicationName() {
        guard presentsFestiveName, let appItem = NSApp.mainMenu?.item(at: 0) else { return }
        ProcessInfo.processInfo.processName = festive
        appItem.title = menuTitle(appItem.title)
        if let submenu = appItem.submenu {
            submenu.title = menuTitle(submenu.title)
            for item in submenu.items {
                item.title = applying(to: item.title)
            }
        }
    }

    /// The application-menu title. A debug display name such as "DOKK Dev" becomes
    /// "BIG DIKK Dev"; a title that never contained the product name becomes ``festive``.
    private static func menuTitle(_ title: String) -> String {
        let renamed = applying(to: title)
        return renamed.contains(festive) ? renamed : festive
    }

    /// Gregorian calendar in `timeZone`, defaulting to the Mac's current zone.
    static func localGregorian(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func replacing(in text: String) -> String {
        guard text.contains(canonical) else { return text }
        return text.replacingOccurrences(of: canonical, with: festive)
    }
}

/// Main bundle during an alias week. Resolves catalog strings and the displayed bundle
/// names through ``ProductAlias``.
nonisolated final class ProductAliasBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        ProductAlias.applying(to: super.localizedString(forKey: key, value: value, table: tableName))
    }

    override var infoDictionary: [String: Any]? {
        ProductAlias.renamingDisplayedNames(in: super.infoDictionary, active: ProductAlias.presentsFestiveName)
    }

    override var localizedInfoDictionary: [String: Any]? {
        ProductAlias.renamingDisplayedNames(in: super.localizedInfoDictionary, active: ProductAlias.presentsFestiveName)
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        let value = super.object(forInfoDictionaryKey: key)
        guard ProductAlias.displayedBundleNameKeys.contains(key), let text = value as? String else { return value }
        return ProductAlias.applying(to: text)
    }
}

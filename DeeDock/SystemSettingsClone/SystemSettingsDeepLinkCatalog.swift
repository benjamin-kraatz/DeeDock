import Foundation

/// Reorganized System Settings destinations and their `x-apple.systempreferences:` IDs.
///
/// Pane identifiers and `?anchor` values are version-fragile. Apple renames extension IDs
/// between Ventura, Sequoia, Tahoe, and later releases. Prefer IDs from
/// `/System/Applications/System Settings.app/Contents/Resources/Sidebar.plist` and
/// community lists (bvanpeski/SystemPreferences, sigo/macos-settings-urls). Update this
/// file when a row opens the wrong pane or only the Settings root.
enum SystemSettingsDeepLinkCatalog {
    /// Categories in sidebar order. Not Apple's sidebar order.
    static let categories: [SystemSettingsCloneCategory] = [
        meAndPrivacy, network, displays, sound, focus, accessibility, general, powerAndPeople,
    ]

    static var allPanes: [SystemSettingsClonePane] {
        categories.flatMap(\.panes)
    }

    static func category(id: SystemSettingsCloneCategory.ID) -> SystemSettingsCloneCategory? {
        categories.first { $0.id == id }
    }
}

/// One sidebar group in the clone's information architecture.
struct SystemSettingsCloneCategory: Identifiable, Hashable {
    enum ID: String, CaseIterable, Sendable {
        case meAndPrivacy
        case network
        case displays
        case sound
        case focus
        case accessibility
        case general
        case powerAndPeople
    }

    let id: ID
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let symbolName: String
    let panes: [SystemSettingsClonePane]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A single row that deep-links into System Settings.
struct SystemSettingsClonePane: Identifiable, Hashable {
    /// Stable catalog identity. Independent of Apple's pane ID, which can change.
    let id: String
    let title: LocalizedStringResource
    let symbolName: String
    /// Extension or preference-pane identifier after `x-apple.systempreferences:`.
    let paneIdentifier: String
    /// Optional fragment after `?`. Omitted when the pane has no reliable anchor.
    let anchor: String?
    /// English lookup tokens so search still finds a row after translation.
    let searchHints: [String]

    init(
        id: String,
        title: LocalizedStringResource,
        symbolName: String,
        paneIdentifier: String,
        anchor: String? = nil,
        searchHints: [String] = []
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.paneIdentifier = paneIdentifier
        self.anchor = anchor
        self.searchHints = searchHints
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// `x-apple.systempreferences:<paneID>` or `x-apple.systempreferences:<paneID>?<anchor>`.
    var url: URL? {
        var specification = "x-apple.systempreferences:\(paneIdentifier)"
        if let anchor, !anchor.isEmpty {
            specification += "?\(anchor)"
        }
        return URL(string: specification)
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if String(localized: title).localizedStandardContains(trimmed) { return true }
        if paneIdentifier.localizedStandardContains(trimmed) { return true }
        if let anchor, anchor.localizedStandardContains(trimmed) { return true }
        return searchHints.contains { $0.localizedStandardContains(trimmed) }
    }
}

extension SystemSettingsCloneCategory {
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if String(localized: title).localizedStandardContains(trimmed) { return true }
        if String(localized: summary).localizedStandardContains(trimmed) { return true }
        return panes.contains { $0.matches(trimmed) }
    }

    func panesMatching(_ query: String) -> [SystemSettingsClonePane] {
        panes.filter { $0.matches(query) }
    }
}

// MARK: - Catalog rows

private extension SystemSettingsDeepLinkCatalog {
    static let meAndPrivacy = SystemSettingsCloneCategory(
        id: .meAndPrivacy,
        title: .systemSettingsCloneCategoryMePrivacy,
        summary: .systemSettingsCloneCategoryMePrivacySummary,
        symbolName: "person.crop.circle.fill",
        panes: [
            pane("apple-account", .systemSettingsClonePaneAppleAccount, "person.crop.circle",
                 "com.apple.systempreferences.AppleIDSettings", hints: ["apple id", "apple account"]),
            pane("icloud", .systemSettingsClonePaneICloud, "icloud",
                 "com.apple.systempreferences.AppleIDSettings", anchor: "iCloud", hints: ["icloud"]),
            pane("family", .systemSettingsClonePaneFamily, "figure.2.and.child.holdinghands",
                 "com.apple.Family-Settings.extension", hints: ["family sharing"]),
            pane("passwords", .systemSettingsClonePanePasswords, "key.fill",
                 "com.apple.Passwords-Settings.extension", hints: ["autofill", "keychain"]),
            pane("wallet", .systemSettingsClonePaneWallet, "creditcard.fill",
                 "com.apple.WalletSettingsExtension", hints: ["apple pay"]),
            pane("internet-accounts", .systemSettingsClonePaneInternetAccounts, "at",
                 "com.apple.Internet-Accounts-Settings.extension", hints: ["mail", "calendars"]),
            pane("game-center", .systemSettingsClonePaneGameCenter, "gamecontroller.fill",
                 "com.apple.Game-Center-Settings.extension"),
            pane("privacy", .systemSettingsClonePanePrivacy, "hand.raised.fill",
                 "com.apple.settings.PrivacySecurity.extension", hints: ["security", "tcc"]),
            pane("privacy-location", .systemSettingsClonePanePrivacyLocation, "location.fill",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "Privacy_LocationServices"),
            pane("privacy-camera", .systemSettingsClonePanePrivacyCamera, "camera.fill",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "Privacy_Camera"),
            pane("privacy-microphone", .systemSettingsClonePanePrivacyMicrophone, "mic.fill",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "Privacy_Microphone"),
            pane("privacy-accessibility", .systemSettingsClonePanePrivacyAccessibility, "accessibility",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "Privacy_Accessibility"),
            pane("privacy-screen", .systemSettingsClonePanePrivacyScreen, "rectangle.dashed.badge.record",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "Privacy_ScreenCapture",
                 hints: ["screen recording"]),
            pane("privacy-full-disk", .systemSettingsClonePanePrivacyFullDisk, "externaldrive.fill.badge.checkmark",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "Privacy_AllFiles",
                 hints: ["full disk access"]),
            pane("privacy-filevault", .systemSettingsClonePanePrivacyFileVault, "lock.rectangle.stack.fill",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "FileVault"),
            pane("privacy-lockdown", .systemSettingsClonePanePrivacyLockdown, "lock.shield.fill",
                 "com.apple.settings.PrivacySecurity.extension", anchor: "LockdownMode"),
        ]
    )

    static let network = SystemSettingsCloneCategory(
        id: .network,
        title: .systemSettingsCloneCategoryNetwork,
        summary: .systemSettingsCloneCategoryNetworkSummary,
        symbolName: "wifi",
        panes: [
            pane("wifi", .systemSettingsClonePaneWiFi, "wifi",
                 "com.apple.wifi-settings-extension", hints: ["wireless"]),
            pane("bluetooth", .systemSettingsClonePaneBluetooth, "airpodspro",
                 "com.apple.BluetoothSettings"),
            pane("network", .systemSettingsClonePaneNetwork, "network",
                 "com.apple.Network-Settings.extension", hints: ["ethernet", "tcp"]),
            pane("vpn", .systemSettingsClonePaneVPN, "lock.shield",
                 "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"),
            pane("airdrop", .systemSettingsClonePaneAirDrop, "dot.radiowaves.left.and.right",
                 "com.apple.AirDrop-Handoff-Settings.extension", hints: ["handoff", "continuity"]),
            pane("sharing", .systemSettingsClonePaneSharing, "shared.with.you",
                 "com.apple.Sharing-Settings.extension", hints: ["file sharing", "remote"]),
        ]
    )

    static let displays = SystemSettingsCloneCategory(
        id: .displays,
        title: .systemSettingsCloneCategoryDisplays,
        summary: .systemSettingsCloneCategoryDisplaysSummary,
        symbolName: "display",
        panes: [
            pane("displays", .systemSettingsClonePaneDisplays, "display",
                 "com.apple.Displays-Settings.extension", hints: ["monitor", "resolution"]),
            pane("appearance", .systemSettingsClonePaneAppearance, "circle.lefthalf.filled",
                 "com.apple.Appearance-Settings.extension", hints: ["dark mode", "accent"]),
            pane("wallpaper", .systemSettingsClonePaneWallpaper, "photo.fill",
                 "com.apple.Wallpaper-Settings.extension"),
            pane("screen-saver", .systemSettingsClonePaneScreenSaver, "moon.stars.fill",
                 "com.apple.ScreenSaver-Settings.extension"),
            pane("desktop-dock", .systemSettingsClonePaneDesktopDock, "dock.rectangle",
                 "com.apple.Desktop-Settings.extension", hints: ["dock", "menu bar"]),
            pane("control-center", .systemSettingsClonePaneControlCenter, "switch.2",
                 "com.apple.ControlCenter-Settings.extension"),
        ]
    )

    static let sound = SystemSettingsCloneCategory(
        id: .sound,
        title: .systemSettingsCloneCategorySound,
        summary: .systemSettingsCloneCategorySoundSummary,
        symbolName: "speaker.wave.2.fill",
        panes: [
            pane("sound", .systemSettingsClonePaneSound, "speaker.wave.2.fill",
                 "com.apple.Sound-Settings.extension", hints: ["output", "input", "volume"]),
            pane("keyboard", .systemSettingsClonePaneKeyboard, "keyboard.fill",
                 "com.apple.Keyboard-Settings.extension", hints: ["shortcuts", "input source"]),
            pane("trackpad", .systemSettingsClonePaneTrackpad, "hand.point.up.left.fill",
                 "com.apple.Trackpad-Settings.extension", hints: ["gestures"]),
            pane("mouse", .systemSettingsClonePaneMouse, "computermouse.fill",
                 "com.apple.Mouse-Settings.extension"),
            pane("headphones", .systemSettingsClonePaneHeadphones, "beats.headphones",
                 "com.apple.HeadphoneSettings", hints: ["airpods"]),
            pane("game-controller", .systemSettingsClonePaneGameController, "gamecontroller",
                 "com.apple.Game-Controller-Settings.extension"),
            // Tahoe+ lists `com.apple.preference.printfax`; Ventura used Print-Scan-Settings.extension.
            pane("printers", .systemSettingsClonePanePrinters, "printer.fill",
                 "com.apple.preference.printfax", hints: ["scanner", "print-scan"]),
            pane("cds", .systemSettingsClonePaneCDs, "opticaldisc.fill",
                 "com.apple.CD-DVD-Settings.extension"),
        ]
    )

    static let focus = SystemSettingsCloneCategory(
        id: .focus,
        title: .systemSettingsCloneCategoryFocus,
        summary: .systemSettingsCloneCategoryFocusSummary,
        symbolName: "moon.fill",
        panes: [
            pane("focus", .systemSettingsClonePaneFocus, "moon.fill",
                 "com.apple.Focus-Settings.extension", hints: ["do not disturb"]),
            pane("notifications", .systemSettingsClonePaneNotifications, "bell.badge.fill",
                 "com.apple.Notifications-Settings.extension"),
            pane("screen-time", .systemSettingsClonePaneScreenTime, "hourglass",
                 "com.apple.Screen-Time-Settings.extension"),
            pane("siri", .systemSettingsClonePaneSiri, "sparkles",
                 "com.apple.Siri-Settings.extension", hints: ["apple intelligence", "siri"]),
            pane("spotlight", .systemSettingsClonePaneSpotlight, "magnifyingglass",
                 "com.apple.Spotlight-Settings.extension"),
        ]
    )

    static let accessibility = SystemSettingsCloneCategory(
        id: .accessibility,
        title: .systemSettingsCloneCategoryAccessibility,
        summary: .systemSettingsCloneCategoryAccessibilitySummary,
        symbolName: "accessibility",
        panes: [
            pane("accessibility", .systemSettingsClonePaneAccessibility, "accessibility",
                 "com.apple.Accessibility-Settings.extension"),
            pane("voiceover", .systemSettingsClonePaneVoiceOver, "ear.fill",
                 "com.apple.Accessibility-Settings.extension", anchor: "VoiceOver"),
            pane("zoom", .systemSettingsClonePaneZoom, "plus.magnifyingglass",
                 "com.apple.Accessibility-Settings.extension", anchor: "Zoom"),
            pane("ax-display", .systemSettingsClonePaneAXDisplay, "circle.lefthalf.striped.horizontal.inverse",
                 "com.apple.Accessibility-Settings.extension", anchor: "Display",
                 hints: ["increase contrast", "reduce motion"]),
            pane("spoken-content", .systemSettingsClonePaneSpokenContent, "text.bubble.fill",
                 "com.apple.Accessibility-Settings.extension", anchor: "SpokenContent"),
            pane("captions", .systemSettingsClonePaneCaptions, "captions.bubble.fill",
                 "com.apple.Accessibility-Settings.extension", anchor: "Captions"),
            pane("voice-control", .systemSettingsClonePaneVoiceControl, "mic.badge.plus",
                 "com.apple.Accessibility-Settings.extension", anchor: "VoiceControl"),
            pane("ax-keyboard", .systemSettingsClonePaneAXKeyboard, "keyboard.badge.ellipsis",
                 "com.apple.Accessibility-Settings.extension", anchor: "Keyboard"),
            pane("pointer-control", .systemSettingsClonePanePointerControl, "cursorarrow.click",
                 "com.apple.Accessibility-Settings.extension", anchor: "PointerControl",
                 hints: ["mouse keys"]),
            pane("live-speech", .systemSettingsClonePaneLiveSpeech, "quote.bubble.fill",
                 "com.apple.Accessibility-Settings.extension", anchor: "LiveSpeech"),
        ]
    )

    static let general = SystemSettingsCloneCategory(
        id: .general,
        title: .systemSettingsCloneCategoryGeneral,
        summary: .systemSettingsCloneCategoryGeneralSummary,
        symbolName: "gearshape.fill",
        panes: [
            pane("general", .systemSettingsClonePaneGeneral, "gearshape.fill",
                 "com.apple.systempreferences.GeneralSettings"),
            pane("about", .systemSettingsClonePaneAbout, "info.circle.fill",
                 "com.apple.SystemProfiler.AboutExtension", hints: ["serial", "macos version"]),
            pane("software-update", .systemSettingsClonePaneSoftwareUpdate, "gear.badge",
                 "com.apple.Software-Update-Settings.extension"),
            pane("storage", .systemSettingsClonePaneStorage, "internaldrive.fill",
                 "com.apple.settings.Storage"),
            pane("coverage", .systemSettingsClonePaneCoverage, "checkmark.seal.fill",
                 "com.apple.Coverage-Settings.extension", hints: ["applecare", "warranty"]),
            pane("language", .systemSettingsClonePaneLanguage, "globe",
                 "com.apple.Localization-Settings.extension", hints: ["region", "locale"]),
            pane("date-time", .systemSettingsClonePaneDateTime, "clock.fill",
                 "com.apple.Date-Time-Settings.extension"),
            pane("time-machine", .systemSettingsClonePaneTimeMachine, "clock.arrow.circlepath",
                 "com.apple.Time-Machine-Settings.extension", hints: ["backup"]),
            pane("transfer-reset", .systemSettingsClonePaneTransferReset, "arrow.triangle.2.circlepath",
                 "com.apple.Transfer-Reset-Settings.extension", hints: ["erase", "migration"]),
            pane("startup-disk", .systemSettingsClonePaneStartupDisk, "internaldrive",
                 "com.apple.Startup-Disk-Settings.extension"),
            pane("login-items", .systemSettingsClonePaneLoginItems, "list.bullet.rectangle.portrait.fill",
                 "com.apple.LoginItems-Settings.extension", hints: ["open at login", "background"]),
            pane("profiles", .systemSettingsClonePaneProfiles, "doc.badge.gearshape",
                 "com.apple.Profiles-Settings.extension", hints: ["mdm", "device management"]),
            pane("extensions", .systemSettingsClonePaneExtensions, "puzzlepiece.extension.fill",
                 "com.apple.ExtensionsPreferences"),
        ]
    )

    static let powerAndPeople = SystemSettingsCloneCategory(
        id: .powerAndPeople,
        title: .systemSettingsCloneCategoryPower,
        summary: .systemSettingsCloneCategoryPowerSummary,
        symbolName: "battery.100percent",
        panes: [
            pane("battery", .systemSettingsClonePaneBattery, "battery.100percent",
                 "com.apple.Battery-Settings.extension", hints: ["energy", "low power"]),
            pane("energy-saver", .systemSettingsClonePaneEnergySaver, "leaf.fill",
                 "com.apple.preferences.EnergySaverPrefPane", hints: ["desktop"]),
            pane("lock-screen", .systemSettingsClonePaneLockScreen, "lock.fill",
                 "com.apple.Lock-Screen-Settings.extension"),
            pane("touch-id", .systemSettingsClonePaneTouchID, "touchid",
                 "com.apple.Touch-ID-Settings.extension", hints: ["password", "login password"]),
            pane("users", .systemSettingsClonePaneUsers, "person.2.fill",
                 "com.apple.Users-Groups-Settings.extension", hints: ["accounts", "guest"]),
        ]
    )

    static func pane(
        _ id: String,
        _ title: LocalizedStringResource,
        _ symbolName: String,
        _ paneIdentifier: String,
        anchor: String? = nil,
        hints: [String] = []
    ) -> SystemSettingsClonePane {
        SystemSettingsClonePane(
            id: id,
            title: title,
            symbolName: symbolName,
            paneIdentifier: paneIdentifier,
            anchor: anchor,
            searchHints: hints
        )
    }
}

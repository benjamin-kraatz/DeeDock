import Foundation

/// Reorganized System Settings destinations and their `x-apple.systempreferences:` IDs.
///
/// Pane identifiers and `?anchor` values are version-fragile. Apple renames extension IDs
/// between Ventura, Sequoia, Tahoe, and later releases. Prefer IDs from
/// `/System/Applications/System Settings.app/Contents/Resources/Sidebar.plist` and
/// community lists (bvanpeski/SystemPreferences, sigo/macos-settings-urls). Update this
/// file when a row opens the wrong pane or only the Settings root.
///
/// Categories group destinations by what people want to do, not by Apple's sidebar.
/// Privacy permissions live together; "This Mac" collects hardware and maintenance.
enum SystemSettingsDeepLinkCatalog {
    /// Categories in canvas order.
    static let categories: [SystemSettingsCloneCategory] = [
        you, connections, lookAndFeel, devices, attention, privacy, accessibility, thisMac, general,
    ]

    static let allPanes: [SystemSettingsClonePane] = categories.flatMap(\.panes)

    static func category(id: SystemSettingsCloneCategory.ID) -> SystemSettingsCloneCategory? {
        categories.first { $0.id == id }
    }

    static func pane(id: String) -> SystemSettingsClonePane? {
        allPanes.first { $0.id == id }
    }

    static func category(containing pane: SystemSettingsClonePane) -> SystemSettingsCloneCategory? {
        categories.first { $0.panes.contains(pane) }
    }

    /// Everyday destinations that fill Quick Access before the person has recents.
    static let popularPaneIDs = ["wifi", "bluetooth", "displays", "sound", "notifications", "privacy", "battery", "desktop-dock"]
}

/// One section in the clone's information architecture.
struct SystemSettingsCloneCategory: Identifiable, Hashable {
    enum ID: String, CaseIterable, Sendable {
        case you
        case connections
        case lookAndFeel
        case devices
        case attention
        case privacy
        case accessibility
        case thisMac
        case general
    }

    let id: ID
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let symbolName: String
    let tint: SystemSettingsCloneTint
    let panes: [SystemSettingsClonePane]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A single destination that deep-links into System Settings.
struct SystemSettingsClonePane: Identifiable, Hashable {
    /// Stable catalog identity. Independent of Apple's pane ID, which can change.
    let id: String
    let title: LocalizedStringResource
    /// One line describing what the person finds inside the pane.
    let detail: LocalizedStringResource
    let symbolName: String
    let tint: SystemSettingsCloneTint
    /// Extension or preference-pane identifier after `x-apple.systempreferences:`.
    let paneIdentifier: String
    /// Optional fragment after `?`. Omitted when the pane has no reliable anchor.
    let anchor: String?
    /// English and German lookup tokens. They are never displayed, so they stay out of
    /// the string catalog; they let "dark mode" or "Dunkelmodus" find Appearance in any UI language.
    let searchHints: [String]

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
}

// MARK: - Catalog

private extension SystemSettingsDeepLinkCatalog {
    static let privacyExtension = "com.apple.settings.PrivacySecurity.extension"
    static let accessibilityExtension = "com.apple.Accessibility-Settings.extension"

    static let you = SystemSettingsCloneCategory(
        id: .you,
        title: .systemSettingsCloneCategoryYou,
        summary: .systemSettingsCloneCategoryYouSummary,
        symbolName: "person.crop.circle.fill",
        tint: .blue,
        panes: [
            pane("apple-account", .systemSettingsClonePaneAppleAccount, .systemSettingsClonePaneAppleAccountDetail,
                 "person.crop.circle.fill", .blue, "com.apple.systempreferences.AppleIDSettings",
                 hints: ["apple id", "sign in", "anmelden", "konto", "devices", "geräte"]),
            pane("icloud", .systemSettingsClonePaneICloud, .systemSettingsClonePaneICloudDetail,
                 "icloud.fill", .cyan, "com.apple.systempreferences.AppleIDSettings", anchor: "iCloud",
                 hints: ["drive", "sync", "photos", "fotos", "backup"]),
            pane("family", .systemSettingsClonePaneFamily, .systemSettingsClonePaneFamilyDetail,
                 "figure.2.and.child.holdinghands", .teal, "com.apple.Family-Settings.extension",
                 hints: ["family sharing", "familienfreigabe", "kids", "kinder", "parental"]),
            pane("passwords", .systemSettingsClonePanePasswords, .systemSettingsClonePanePasswordsDetail,
                 "key.fill", .graphite, "com.apple.Passwords-Settings.extension",
                 hints: ["autofill", "keychain", "schlüsselbund", "passkey"]),
            pane("wallet", .systemSettingsClonePaneWallet, .systemSettingsClonePaneWalletDetail,
                 "wallet.pass.fill", .graphite, "com.apple.WalletSettingsExtension",
                 hints: ["apple pay", "credit card", "kreditkarte", "payment", "bezahlen"]),
            pane("internet-accounts", .systemSettingsClonePaneInternetAccounts, .systemSettingsClonePaneInternetAccountsDetail,
                 "at", .blue, "com.apple.Internet-Accounts-Settings.extension",
                 hints: ["mail", "calendar", "kalender", "google", "exchange", "contacts", "kontakte"]),
            pane("game-center", .systemSettingsClonePaneGameCenter, .systemSettingsClonePaneGameCenterDetail,
                 "gamecontroller.fill", .pink, "com.apple.Game-Center-Settings.extension",
                 hints: ["games", "spiele", "friends", "freunde"]),
            pane("users", .systemSettingsClonePaneUsers, .systemSettingsClonePaneUsersDetail,
                 "person.2.fill", .indigo, "com.apple.Users-Groups-Settings.extension",
                 hints: ["accounts", "guest", "gast", "admin", "benutzer"]),
        ]
    )

    static let connections = SystemSettingsCloneCategory(
        id: .connections,
        title: .systemSettingsCloneCategoryConnections,
        summary: .systemSettingsCloneCategoryConnectionsSummary,
        symbolName: "wifi",
        tint: .cyan,
        panes: [
            pane("wifi", .systemSettingsClonePaneWiFi, .systemSettingsClonePaneWiFiDetail,
                 "wifi", .blue, "com.apple.wifi-settings-extension",
                 hints: ["wireless", "wlan", "internet", "hotspot", "funk"]),
            pane("bluetooth", .systemSettingsClonePaneBluetooth, .systemSettingsClonePaneBluetoothDetail,
                 "dot.radiowaves.forward", .blue, "com.apple.BluetoothSettings",
                 hints: ["airpods", "pair", "koppeln", "accessories", "zubehör"]),
            pane("network", .systemSettingsClonePaneNetwork, .systemSettingsClonePaneNetworkDetail,
                 "network", .blue, "com.apple.Network-Settings.extension",
                 hints: ["ethernet", "tcp", "dns", "firewall", "proxy", "lan"]),
            pane("vpn", .systemSettingsClonePaneVPN, .systemSettingsClonePaneVPNDetail,
                 "lock.shield.fill", .indigo, "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension",
                 hints: ["tunnel", "wireguard"]),
            pane("airdrop", .systemSettingsClonePaneAirDrop, .systemSettingsClonePaneAirDropDetail,
                 "airplay.audio", .cyan, "com.apple.AirDrop-Handoff-Settings.extension",
                 hints: ["handoff", "continuity", "airplay", "universal clipboard"]),
            pane("sharing", .systemSettingsClonePaneSharing, .systemSettingsClonePaneSharingDetail,
                 "folder.fill.badge.person.crop", .gray, "com.apple.Sharing-Settings.extension",
                 hints: ["file sharing", "dateifreigabe", "remote", "ssh", "screen sharing", "computer name", "hostname"]),
        ]
    )

    static let lookAndFeel = SystemSettingsCloneCategory(
        id: .lookAndFeel,
        title: .systemSettingsCloneCategoryLookAndFeel,
        summary: .systemSettingsCloneCategoryLookAndFeelSummary,
        symbolName: "paintpalette.fill",
        tint: .orange,
        panes: [
            pane("appearance", .systemSettingsClonePaneAppearance, .systemSettingsClonePaneAppearanceDetail,
                 "circle.lefthalf.filled", .graphite, "com.apple.Appearance-Settings.extension",
                 hints: ["dark mode", "dunkelmodus", "light mode", "accent", "akzentfarbe", "theme", "icon"]),
            pane("wallpaper", .systemSettingsClonePaneWallpaper, .systemSettingsClonePaneWallpaperDetail,
                 "photo.fill", .cyan, "com.apple.Wallpaper-Settings.extension",
                 hints: ["background", "hintergrundbild", "desktop picture"]),
            pane("displays", .systemSettingsClonePaneDisplays, .systemSettingsClonePaneDisplaysDetail,
                 "sun.max.fill", .blue, "com.apple.Displays-Settings.extension",
                 hints: ["monitor", "resolution", "auflösung", "brightness", "helligkeit", "night shift", "bildschirm"]),
            pane("screen-saver", .systemSettingsClonePaneScreenSaver, .systemSettingsClonePaneScreenSaverDetail,
                 "moon.stars.fill", .teal, "com.apple.ScreenSaver-Settings.extension"),
            pane("desktop-dock", .systemSettingsClonePaneDesktopDock, .systemSettingsClonePaneDesktopDockDetail,
                 "dock.rectangle", .graphite, "com.apple.Desktop-Settings.extension",
                 hints: ["dock", "stage manager", "hot corners", "aktive ecken", "windows", "fenster", "widgets", "mission control"]),
            pane("control-center", .systemSettingsClonePaneControlCenter, .systemSettingsClonePaneControlCenterDetail,
                 "switch.2", .gray, "com.apple.ControlCenter-Settings.extension",
                 hints: ["menu bar", "menüleiste", "clock", "battery percentage"]),
        ]
    )

    static let devices = SystemSettingsCloneCategory(
        id: .devices,
        title: .systemSettingsCloneCategoryDevices,
        summary: .systemSettingsCloneCategoryDevicesSummary,
        symbolName: "speaker.wave.2.fill",
        tint: .pink,
        panes: [
            pane("sound", .systemSettingsClonePaneSound, .systemSettingsClonePaneSoundDetail,
                 "speaker.wave.2.fill", .pink, "com.apple.Sound-Settings.extension",
                 hints: ["audio", "volume", "lautstärke", "output", "input", "alert", "speaker", "lautsprecher"]),
            pane("headphones", .systemSettingsClonePaneHeadphones, .systemSettingsClonePaneHeadphonesDetail,
                 "airpodspro", .indigo, "com.apple.HeadphoneSettings",
                 hints: ["airpods", "spatial audio", "noise cancellation"]),
            pane("keyboard", .systemSettingsClonePaneKeyboard, .systemSettingsClonePaneKeyboardDetail,
                 "keyboard.fill", .graphite, "com.apple.Keyboard-Settings.extension",
                 hints: ["shortcuts", "kurzbefehle", "input source", "dictation", "diktat", "backlight", "key repeat"]),
            pane("trackpad", .systemSettingsClonePaneTrackpad, .systemSettingsClonePaneTrackpadDetail,
                 "rectangle.and.hand.point.up.left.fill", .gray, "com.apple.Trackpad-Settings.extension",
                 hints: ["gestures", "gesten", "tap to click", "scroll", "force click"]),
            pane("mouse", .systemSettingsClonePaneMouse, .systemSettingsClonePaneMouseDetail,
                 "computermouse.fill", .gray, "com.apple.Mouse-Settings.extension",
                 hints: ["scroll direction", "natural scrolling", "rechtsklick", "right click"]),
            pane("game-controller", .systemSettingsClonePaneGameController, .systemSettingsClonePaneGameControllerDetail,
                 "gamecontroller.fill", .green, "com.apple.Game-Controller-Settings.extension",
                 hints: ["playstation", "xbox", "gamepad"]),
            // Tahoe+ lists `com.apple.preference.printfax`; Ventura used Print-Scan-Settings.extension.
            pane("printers", .systemSettingsClonePanePrinters, .systemSettingsClonePanePrintersDetail,
                 "printer.fill", .gray, "com.apple.preference.printfax",
                 hints: ["scanner", "print", "drucken"]),
            pane("cds", .systemSettingsClonePaneCDs, .systemSettingsClonePaneCDsDetail,
                 "opticaldisc.fill", .gray, "com.apple.CD-DVD-Settings.extension"),
        ]
    )

    static let attention = SystemSettingsCloneCategory(
        id: .attention,
        title: .systemSettingsCloneCategoryAttention,
        summary: .systemSettingsCloneCategoryAttentionSummary,
        symbolName: "bell.badge.fill",
        tint: .red,
        panes: [
            pane("notifications", .systemSettingsClonePaneNotifications, .systemSettingsClonePaneNotificationsDetail,
                 "bell.badge.fill", .red, "com.apple.Notifications-Settings.extension",
                 hints: ["banner", "badges", "alerts", "benachrichtigungen", "hinweise"]),
            pane("focus", .systemSettingsClonePaneFocus, .systemSettingsClonePaneFocusDetail,
                 "moon.fill", .indigo, "com.apple.Focus-Settings.extension",
                 hints: ["do not disturb", "nicht stören", "dnd", "silence"]),
            pane("screen-time", .systemSettingsClonePaneScreenTime, .systemSettingsClonePaneScreenTimeDetail,
                 "hourglass", .purple, "com.apple.Screen-Time-Settings.extension",
                 hints: ["app limits", "downtime", "auszeit", "parental controls", "kindersicherung"]),
            pane("siri", .systemSettingsClonePaneSiri, .systemSettingsClonePaneSiriDetail,
                 "sparkles", .iris, "com.apple.Siri-Settings.extension",
                 hints: ["apple intelligence", "assistant", "ai", "ki", "hey siri", "chatgpt"]),
            pane("spotlight", .systemSettingsClonePaneSpotlight, .systemSettingsClonePaneSpotlightDetail,
                 "magnifyingglass", .gray, "com.apple.Spotlight-Settings.extension",
                 hints: ["search", "suche", "index"]),
        ]
    )

    static let privacy = SystemSettingsCloneCategory(
        id: .privacy,
        title: .systemSettingsCloneCategoryPrivacy,
        summary: .systemSettingsCloneCategoryPrivacySummary,
        symbolName: "hand.raised.fill",
        tint: .teal,
        panes: [
            pane("privacy", .systemSettingsClonePanePrivacy, .systemSettingsClonePanePrivacyDetail,
                 "hand.raised.fill", .blue, privacyExtension,
                 hints: ["security", "sicherheit", "permissions", "berechtigungen", "tcc", "gatekeeper"]),
            pane("privacy-location", .systemSettingsClonePanePrivacyLocation, .systemSettingsClonePanePrivacyLocationDetail,
                 "location.fill", .blue, privacyExtension, anchor: "Privacy_LocationServices",
                 hints: ["gps", "standort", "location"]),
            pane("privacy-camera", .systemSettingsClonePanePrivacyCamera, .systemSettingsClonePanePrivacyCameraDetail,
                 "camera.fill", .graphite, privacyExtension, anchor: "Privacy_Camera",
                 hints: ["webcam", "facetime"]),
            pane("privacy-microphone", .systemSettingsClonePanePrivacyMicrophone, .systemSettingsClonePanePrivacyMicrophoneDetail,
                 "mic.fill", .orange, privacyExtension, anchor: "Privacy_Microphone",
                 hints: ["mic", "recording", "aufnahme"]),
            pane("privacy-screen", .systemSettingsClonePanePrivacyScreen, .systemSettingsClonePanePrivacyScreenDetail,
                 "record.circle", .purple, privacyExtension, anchor: "Privacy_ScreenCapture",
                 hints: ["screen recording", "bildschirmaufnahme", "screenshot", "capture"]),
            pane("privacy-accessibility", .systemSettingsClonePanePrivacyAccessibility, .systemSettingsClonePanePrivacyAccessibilityDetail,
                 "accessibility", .blue, privacyExtension, anchor: "Privacy_Accessibility",
                 hints: ["control computer", "automation", "window manager"]),
            pane("privacy-input-monitoring", .systemSettingsClonePanePrivacyInputMonitoring,
                 .systemSettingsClonePanePrivacyInputMonitoringDetail,
                 "keyboard.badge.eye", .gray, privacyExtension, anchor: "Privacy_ListenEvent",
                 hints: ["keylogger", "eingabeüberwachung", "listen event"]),
            pane("privacy-automation", .systemSettingsClonePanePrivacyAutomation, .systemSettingsClonePanePrivacyAutomationDetail,
                 "gearshape.2.fill", .gray, privacyExtension, anchor: "Privacy_Automation",
                 hints: ["applescript", "apple events", "automatisierung"]),
            pane("privacy-app-management", .systemSettingsClonePanePrivacyAppManagement,
                 .systemSettingsClonePanePrivacyAppManagementDetail,
                 "square.stack.3d.up.fill", .blue, privacyExtension, anchor: "Privacy_AppBundles",
                 hints: ["app verwaltung", "updater"]),
            pane("privacy-full-disk", .systemSettingsClonePanePrivacyFullDisk, .systemSettingsClonePanePrivacyFullDiskDetail,
                 "externaldrive.fill", .gray, privacyExtension, anchor: "Privacy_AllFiles",
                 hints: ["full disk access", "festplattenvollzugriff", "files"]),
            pane("privacy-filevault", .systemSettingsClonePanePrivacyFileVault, .systemSettingsClonePanePrivacyFileVaultDetail,
                 "lock.rectangle.stack.fill", .graphite, privacyExtension, anchor: "FileVault",
                 hints: ["encryption", "verschlüsselung", "encrypt"]),
            pane("privacy-lockdown", .systemSettingsClonePanePrivacyLockdown, .systemSettingsClonePanePrivacyLockdownDetail,
                 "lock.shield.fill", .blue, privacyExtension, anchor: "LockdownMode",
                 hints: ["spyware", "targeted attack"]),
            pane("lock-screen", .systemSettingsClonePaneLockScreen, .systemSettingsClonePaneLockScreenDetail,
                 "lock.fill", .graphite, "com.apple.Lock-Screen-Settings.extension",
                 hints: ["screen lock", "bildschirmsperre", "sleep", "ruhezustand", "require password"]),
            pane("touch-id", .systemSettingsClonePaneTouchID, .systemSettingsClonePaneTouchIDDetail,
                 "touchid", .red, "com.apple.Touch-ID-Settings.extension",
                 hints: ["fingerprint", "fingerabdruck", "login password", "passwort ändern", "change password"]),
        ]
    )

    static let accessibility = SystemSettingsCloneCategory(
        id: .accessibility,
        title: .systemSettingsCloneCategoryAccessibility,
        summary: .systemSettingsCloneCategoryAccessibilitySummary,
        symbolName: "accessibility",
        tint: .purple,
        panes: [
            pane("accessibility", .systemSettingsClonePaneAccessibility, .systemSettingsClonePaneAccessibilityDetail,
                 "accessibility", .blue, accessibilityExtension,
                 hints: ["a11y", "barrierefreiheit"]),
            pane("voiceover", .systemSettingsClonePaneVoiceOver, .systemSettingsClonePaneVoiceOverDetail,
                 "speaker.wave.2.bubble.fill", .graphite, accessibilityExtension, anchor: "VoiceOver",
                 hints: ["screen reader", "bildschirmleser", "braille"]),
            pane("zoom", .systemSettingsClonePaneZoom, .systemSettingsClonePaneZoomDetail,
                 "plus.magnifyingglass", .graphite, accessibilityExtension, anchor: "Zoom",
                 hints: ["magnifier", "lupe", "vergrößern"]),
            pane("ax-display", .systemSettingsClonePaneAXDisplay, .systemSettingsClonePaneAXDisplayDetail,
                 "circle.lefthalf.striped.horizontal.inverse", .blue, accessibilityExtension, anchor: "Display",
                 hints: ["increase contrast", "kontrast", "reduce motion", "bewegung reduzieren",
                         "reduce transparency", "transparenz", "color filter", "cursor size"]),
            pane("spoken-content", .systemSettingsClonePaneSpokenContent, .systemSettingsClonePaneSpokenContentDetail,
                 "text.bubble.fill", .teal, accessibilityExtension, anchor: "SpokenContent",
                 hints: ["text to speech", "vorlesen", "speak selection"]),
            pane("captions", .systemSettingsClonePaneCaptions, .systemSettingsClonePaneCaptionsDetail,
                 "captions.bubble.fill", .graphite, accessibilityExtension, anchor: "Captions",
                 hints: ["subtitles", "live captions"]),
            pane("voice-control", .systemSettingsClonePaneVoiceControl, .systemSettingsClonePaneVoiceControlDetail,
                 "mic.badge.plus", .blue, accessibilityExtension, anchor: "VoiceControl",
                 hints: ["voice commands", "sprachbefehle"]),
            pane("ax-keyboard", .systemSettingsClonePaneAXKeyboard, .systemSettingsClonePaneAXKeyboardDetail,
                 "keyboard.badge.ellipsis", .graphite, accessibilityExtension, anchor: "Keyboard",
                 hints: ["sticky keys", "slow keys", "full keyboard access", "einrastfunktion", "tastaturnavigation"]),
            pane("pointer-control", .systemSettingsClonePanePointerControl, .systemSettingsClonePanePointerControlDetail,
                 "cursorarrow.click.2", .blue, accessibilityExtension, anchor: "PointerControl",
                 hints: ["mouse keys", "maustasten", "head pointer", "dwell"]),
            pane("live-speech", .systemSettingsClonePaneLiveSpeech, .systemSettingsClonePaneLiveSpeechDetail,
                 "quote.bubble.fill", .teal, accessibilityExtension, anchor: "LiveSpeech",
                 hints: ["type to speak", "personal voice"]),
        ]
    )

    static let thisMac = SystemSettingsCloneCategory(
        id: .thisMac,
        title: .systemSettingsCloneCategoryThisMac,
        summary: .systemSettingsCloneCategoryThisMacSummary,
        symbolName: "laptopcomputer",
        tint: .graphite,
        panes: [
            pane("about", .systemSettingsClonePaneAbout, .systemSettingsClonePaneAboutDetail,
                 "info.circle.fill", .gray, "com.apple.SystemProfiler.AboutExtension",
                 hints: ["serial", "seriennummer", "macos version", "chip", "model", "about this mac", "über diesen mac"]),
            pane("software-update", .systemSettingsClonePaneSoftwareUpdate, .systemSettingsClonePaneSoftwareUpdateDetail,
                 "arrow.down.circle.fill", .blue, "com.apple.Software-Update-Settings.extension",
                 hints: ["update", "upgrade", "aktualisieren", "beta"]),
            pane("storage", .systemSettingsClonePaneStorage, .systemSettingsClonePaneStorageDetail,
                 "internaldrive.fill", .gray, "com.apple.settings.Storage",
                 hints: ["disk space", "speicherplatz", "free up", "platz", "ssd"]),
            pane("battery", .systemSettingsClonePaneBattery, .systemSettingsClonePaneBatteryDetail,
                 "battery.100percent", .green, "com.apple.Battery-Settings.extension",
                 hints: ["energy", "akku", "low power", "stromsparen", "charging", "laden", "battery health"]),
            pane("energy-saver", .systemSettingsClonePaneEnergySaver, .systemSettingsClonePaneEnergySaverDetail,
                 "bolt.fill", .yellow, "com.apple.preferences.EnergySaverPrefPane",
                 hints: ["desktop", "sleep", "wake", "power", "strom"]),
            pane("time-machine", .systemSettingsClonePaneTimeMachine, .systemSettingsClonePaneTimeMachineDetail,
                 "clock.arrow.circlepath", .green, "com.apple.Time-Machine-Settings.extension",
                 hints: ["backup", "sicherung", "restore"]),
            pane("coverage", .systemSettingsClonePaneCoverage, .systemSettingsClonePaneCoverageDetail,
                 "checkmark.seal.fill", .red, "com.apple.Coverage-Settings.extension",
                 hints: ["applecare", "warranty", "garantie", "repair", "reparatur"]),
            pane("startup-disk", .systemSettingsClonePaneStartupDisk, .systemSettingsClonePaneStartupDiskDetail,
                 "externaldrive.fill.badge.checkmark", .gray, "com.apple.Startup-Disk-Settings.extension",
                 hints: ["boot", "booten"]),
            pane("transfer-reset", .systemSettingsClonePaneTransferReset, .systemSettingsClonePaneTransferResetDetail,
                 "arrow.triangle.2.circlepath", .gray, "com.apple.Transfer-Reset-Settings.extension",
                 hints: ["erase", "löschen", "factory reset", "migration", "sell", "verkaufen"]),
        ]
    )

    static let general = SystemSettingsCloneCategory(
        id: .general,
        title: .systemSettingsCloneCategoryGeneral,
        summary: .systemSettingsCloneCategoryGeneralSummary,
        symbolName: "gearshape.fill",
        tint: .gray,
        panes: [
            pane("general", .systemSettingsClonePaneGeneral, .systemSettingsClonePaneGeneralDetail,
                 "gearshape.fill", .gray, "com.apple.systempreferences.GeneralSettings"),
            pane("language", .systemSettingsClonePaneLanguage, .systemSettingsClonePaneLanguageDetail,
                 "globe", .blue, "com.apple.Localization-Settings.extension",
                 hints: ["region", "locale", "sprache", "format", "calendar", "temperature", "celsius"]),
            pane("date-time", .systemSettingsClonePaneDateTime, .systemSettingsClonePaneDateTimeDetail,
                 "clock.fill", .blue, "com.apple.Date-Time-Settings.extension",
                 hints: ["time zone", "zeitzone", "clock", "uhr", "24-hour"]),
            pane("login-items", .systemSettingsClonePaneLoginItems, .systemSettingsClonePaneLoginItemsDetail,
                 "power", .gray, "com.apple.LoginItems-Settings.extension",
                 hints: ["open at login", "startup apps", "autostart", "background", "hintergrund"]),
            pane("extensions", .systemSettingsClonePaneExtensions, .systemSettingsClonePaneExtensionsDetail,
                 "puzzlepiece.extension.fill", .gray, "com.apple.ExtensionsPreferences",
                 hints: ["share menu", "finder extensions", "quick look"]),
            pane("profiles", .systemSettingsClonePaneProfiles, .systemSettingsClonePaneProfilesDetail,
                 "checkmark.shield.fill", .gray, "com.apple.Profiles-Settings.extension",
                 hints: ["mdm", "device management", "configuration profile", "profile", "profil"]),
        ]
    )

    static func pane(
        _ id: String,
        _ title: LocalizedStringResource,
        _ detail: LocalizedStringResource,
        _ symbolName: String,
        _ tint: SystemSettingsCloneTint,
        _ paneIdentifier: String,
        anchor: String? = nil,
        hints: [String] = []
    ) -> SystemSettingsClonePane {
        SystemSettingsClonePane(
            id: id,
            title: title,
            detail: detail,
            symbolName: symbolName,
            tint: tint,
            paneIdentifier: paneIdentifier,
            anchor: anchor,
            searchHints: hints
        )
    }
}

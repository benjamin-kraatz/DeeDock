import AppKit

/// Login-item registration as macOS reports it.
nonisolated enum AnalyticsLoginItem: String, AnalyticsToken {
    case notRegistered = "not_registered", enabled, requiresApproval = "requires_approval"
    case notFound = "not_found", unknown

    init(_ status: LoginItemStatus) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        case .unknown: self = .unknown
        }
    }
}

/// Live app state the analytics context is computed from.
///
/// The composition root fills this in from the stores it owns, so nothing under `Analytics/`
/// reaches into the dock. No field can hold a display name, an app name, or a path.
struct AnalyticsContextInputs {
    /// One connected display and, when it hosts a dock, that dock's configuration.
    struct Display {
        var isMain: Bool
        var isBuiltIn: Bool
        /// Logical size in points.
        var size: CGSize
        var scale: Double
        /// False when the display's dock is switched off or the display is mirrored.
        var hostsDock: Bool
        /// The settings this dock runs with after applying the display's overrides.
        var settings: DockSettings
        /// How many settings this display overrides instead of inheriting.
        var overrideCount: Int
        var pinnedAppCount: Int
        var pinnedFolderCount: Int
        var runningAppCount: Int
    }

    var displays: [Display] = []
    var sharedSettings: DockSettings = .defaults
    var modeCount = 1
    var loginItem: LoginItemStatus = .unknown
    var accessibility: AnalyticsPermissionStatus = .unavailable
    var screenRecording: AnalyticsPermissionStatus = .unavailable
    /// Whether the macOS Dock has released its desktop space.
    var systemDockHidden = false
    /// Nil in builds that do not update themselves.
    var updates: Updates?

    struct Updates {
        var checksAutomatically: Bool
        var installsAutomatically: Bool
        var installsWhenIdle: Bool
    }
}

/// Builds the properties registered on every event and the fuller set stored on the person profile.
enum AnalyticsContext {
    /// Context plus the key configuration of the main dock, attached to every event.
    static func superProperties(_ inputs: AnalyticsContextInputs) -> AnalyticsProperties {
        var result = AnalyticsSystemContext.properties
        result.merge([
            "display_count": AnalyticsValue(inputs.displays.count),
            "builtin_display_count": AnalyticsValue(inputs.displays.count(where: \.isBuiltIn)),
            "external_display_count": AnalyticsValue(inputs.displays.count { !$0.isBuiltIn }),
            "dock_count": AnalyticsValue(inputs.displays.count(where: \.hostsDock)),
            "dock_mode_count": AnalyticsValue(inputs.modeCount),
            "system_dock_hidden": AnalyticsValue(inputs.systemDockHidden),
            "login_item": AnalyticsValue(AnalyticsLoginItem(inputs.loginItem)),
            "accessibility_access": AnalyticsValue(inputs.accessibility),
            "screen_recording_access": AnalyticsValue(inputs.screenRecording),
            "updates_check_automatically": inputs.updates.map { AnalyticsValue($0.checksAutomatically) },
            "updates_install_automatically": inputs.updates.map { AnalyticsValue($0.installsAutomatically) },
            "updates_install_when_idle": inputs.updates.map { AnalyticsValue($0.installsWhenIdle) },
        ])
        for (scope, display) in scoped(inputs.displays) {
            let kind: AnalyticsProperties = [
                "display_builtin": AnalyticsValue(display.isBuiltIn),
                "display_width": AnalyticsValue(Double(display.size.width)),
                "display_height": AnalyticsValue(Double(display.size.height)),
                "display_scale": AnalyticsValue(display.scale),
            ]
            result.merge(kind.scoped(scope))
        }
        result.merge(keyConfiguration(inputs.displays.first(where: \.isMain)?.settings ?? inputs.sharedSettings))
        return result
    }

    /// Everything in ``superProperties(_:)`` plus the complete configuration: the shared
    /// defaults and, per display, the effective settings and the pin and running-app counts.
    static func personProperties(_ inputs: AnalyticsContextInputs) -> AnalyticsProperties {
        var result = superProperties(inputs)
        result.merge(AnalyticsProperties(reflecting: inputs.sharedSettings, scope: .shared))
        for (scope, display) in scoped(inputs.displays) {
            result.merge(AnalyticsProperties(reflecting: display.settings, scope: scope))
            result.merge(counts(display).scoped(scope))
        }
        return result
    }

    /// Per-display counts for the periodic summary.
    static func summaryProperties(_ inputs: AnalyticsContextInputs) -> AnalyticsProperties {
        var result = AnalyticsProperties()
        for (scope, display) in scoped(inputs.displays) { result.merge(counts(display).scoped(scope)) }
        return result
    }

    private static func counts(_ display: AnalyticsContextInputs.Display) -> AnalyticsProperties {
        ["dock_enabled": AnalyticsValue(display.hostsDock),
         "overrides_shared_defaults": AnalyticsValue(display.overrideCount > 0),
         "override_count": AnalyticsValue(display.overrideCount),
         "pinned_app_count": AnalyticsValue(display.pinnedAppCount),
         "pinned_folder_count": AnalyticsValue(display.pinnedFolderCount),
         "running_app_count": AnalyticsValue(display.runningAppCount)]
    }

    /// The main display first, then the others numbered in the order they were given.
    private static func scoped(_ displays: [AnalyticsContextInputs.Display])
        -> [(AnalyticsScope, AnalyticsContextInputs.Display)] {
        var secondary = 0
        return displays.map { display in
            if display.isMain { return (.mainDisplay, display) }
            secondary += 1
            return (.secondaryDisplay(secondary), display)
        }
    }

    /// The handful of settings worth having on every event without a person-profile join.
    private static func keyConfiguration(_ settings: DockSettings) -> AnalyticsProperties {
        ["dock_edge": AnalyticsValue(settings.edge),
         "dock_alignment": AnalyticsValue(settings.alignment),
         "dock_position_reference": AnalyticsValue(settings.positionReference),
         "dock_icon_size": AnalyticsValue(settings.iconSize),
         "dock_magnification": AnalyticsValue(settings.magnification),
         "dock_auto_hide": AnalyticsValue(settings.behavior.autoHide),
         "dock_activation_location": AnalyticsValue(settings.behavior.activationLocation),
         "dock_animation_style": AnalyticsValue(settings.behavior.animationStyle),
         "dock_indicator_style": AnalyticsValue(settings.runningIndicatorStyle),
         "dock_icon_style": AnalyticsValue(settings.iconStyle),
         "dock_launcher_line_icons": AnalyticsValue(settings.launcherLineIcons),
         "dock_tooltip_preset": AnalyticsValue(settings.tooltipPreset),
         "dock_launch_animation": AnalyticsValue(settings.launchAnimation),
         "dock_show_background": AnalyticsValue(settings.showBackground),
         "dock_fade_when_idle": AnalyticsValue(settings.fadeWhenIdle),
         "window_peek_enabled": AnalyticsValue(settings.windowPeekEnabled),
         "window_peek_layout": AnalyticsValue(settings.windowPeekLayout),
         "show_shelf": AnalyticsValue(settings.showShelf),
         "show_trash": AnalyticsValue(settings.showTrash),
         "show_session_capsules": AnalyticsValue(settings.showSessionCapsules),
         "show_volumes": AnalyticsValue(settings.showVolumes),
         "soap_bubble_effects": AnalyticsValue(settings.soapBubbleEffects)]
    }
}

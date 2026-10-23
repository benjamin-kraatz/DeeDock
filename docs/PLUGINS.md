# DOKK Plugins

A DOKK plugin is an ExtensionKit extension that ships inside another app. Once the person turns it on, it gets its own tile in the dock and a panel above that tile. DOKK draws the tile, the panel's glass, header, and pointer, and the stopped state. Everything below the panel's header is the plugin's own SwiftUI, running in the plugin's process.

This page is for people building a plugin. The [user guide](GUIDE.md#plugins) describes what people see, and the [acceptance notes](ACCEPTANCE.md#dokk-plugins-dee-140) record what has been checked. The look comes from the locked mockup `docs/mockups/dokk-plugins.html`.

## What a plugin needs

1. An app that carries the extension in `Contents/Extensions`. Installing the app is what makes macOS aware of the plugin.
2. An ExtensionKit extension target (`com.apple.product-type.extensionkit-extension`) that:
   - binds to DOKK's extension point;
   - provides a panel scene with the ID `dokk-plugin-panel`;
   - accepts DOKK's XPC connections.
3. A copy of `DOKKPluginContract/`, compiled into the extension. That folder is the contract: keep it unchanged.

The `DOKK Sample Plugin` scheme in this repository builds a complete example from `DOKKPluginSample/`. Copy `DOKKPluginSample/Extension/DOKKPluginHostLink.swift` too: it handles every DOKK connection for you.

### Bind to the extension point

DOKK and DOKK Dev both declare one extension point, `de.benjaminkraatz.DeeDock.dev.plugin`, so a plugin built against either loads in both. Bind to it with the host and name spelled out as literals:

```swift
@main
struct MyPlugin: AppExtension {
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "de.benjaminkraatz.DeeDock.dev", name: "plugin")
    }

    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(MyPanelScene(),
                                       configuration: ConnectionHandler(onConnection: { MyPlugin.accept($0) }))
    }
}
```

Also state the binding in the extension's Info.plist (`INFOPLIST_FILE`), as `DOKKPluginSample/SamplePluginExtension-Info.plist` does:

```xml
<key>EXAppExtensionAttributes</key>
<dict>
	<key>EXExtensionPointIdentifier</key>
	<string>de.benjaminkraatz.DeeDock.dev.plugin</string>
</dict>
```

Xcode derives that key from `@AppExtensionPoint.Bind` with `exutil generate-appextension-plist`. In Xcode 27.0 (27A266a), that step is unreliable once the target has more than one Swift file: the same inputs sometimes produce the key and sometimes an empty plist. Without the key the extension binds to nothing, and DOKK never sees it. The step also writes nothing for the single-string `Identifier(_:)`, which is why the Bind uses `host:name:`.

### Provide the panel scene

```swift
struct MyPanelScene: AppExtensionScene {
    var body: some AppExtensionScene {
        PrimitiveAppExtensionScene(id: DOKKPluginContract.panelSceneID) {
            MyPanelView()
        } onConnection: { MyPlugin.accept($0) }
    }
}
```

Leave the panel view without a background, so DOKK's glass shows through. Pad your content yourself. DOKK's header sits above it.

### Accept DOKK's connections

DOKK opens one background connection while the plugin's tile is pinned, through `AppExtensionProcess`. That connection reaches the plugin's `ConnectionHandler` and carries the tile state, whether or not the panel is open. The plugin spike measured the panel's scene and this connection reaching the same process.

ExtensionKit calls `ConnectionHandler` and `onConnection` off the main thread. `DOKKPluginHostLink.accept(_:)` is safe to call from there. `SamplePluginModel.accept(_:)` shows how to reach a main-actor link.

## The contract

All values travel as JSON over two `@objc` protocols in `DOKKPluginXPC.swift`. Only DOKK's single `Data` arguments cross XPC, so the Objective-C shape never changes when a value gains a field.

| Direction | Call | Payload |
| --- | --- | --- |
| DOKK → plugin | `connect(_:reply:)` | `DOKKPluginHostInfo` in, `DOKKPluginTileState` back. The first call on every connection. |
| DOKK → plugin | `fetchTileState(reply:)` | `DOKKPluginTileState` back. Sent when the Plugins settings page opens. |
| DOKK → plugin | `handle(_:)` | `DOKKPluginHostEvent`: `panelOpened`, `panelClosed`, `menuItemChosen(id)`, `willDisconnect` |
| Plugin → DOKK | `tileStateDidChange(_:)` | `DOKKPluginTileState`. Send it on every change. DOKK keeps only the latest. |
| Plugin → DOKK | `perform(_:)` | `DOKKPluginRequest`: `closePanel`, `openApp` |

`DOKKPluginTileState` fields, all optional on the wire:

| Field | Meaning |
| --- | --- |
| `contractVersion` | The sender's contract version, `1` today |
| `title` | The tile's name in tooltips, menus, and VoiceOver. Defaults to the extension's display name. |
| `badge` | `count(Int)`, `text(String)`, or `dot`. Drawn like an app badge: no badge at 0, `99+` above 99, text cut to 4 characters. Hidden while the plugin is stopped. |
| `accessibilityValue` | What VoiceOver reads after the title, such as "2 new highlights" |
| `panelSize` | The content size the plugin would like, in points, below DOKK's header |
| `primaryAction` | `openPanel` (the default) or `openApp`: what a click on the tile does |
| `menuItems` | Up to 4 extra commands in the tile's menu, each with an `id`, a localized `title`, and an optional SF Symbol name |

### Versioning

Both sides skip what they don't know:
- missing or unreadable fields fall back to their defaults;
- unknown badge kinds read as no badge;
- unknown click actions read as `openPanel`;
- unknown events and requests are dropped.

So adding an optional field or a new event kind doesn't change the version. The version goes up only for a change an older peer can't ignore.

There is deliberately no request to open the panel. A panel opens only when the person clicks the tile.

## Panel size

DOKK owns the panel's frame. The remote scene reports no usable preferred size: the spike saw `preferredContentSize` stay zero. So the plugin states one in `panelSize`. DOKK sizes the panel like this:
- adds its 40 pt header and the 10 pt pointer (height for a bottom or top dock, width for a side dock);
- keeps the result between the shared popover minimum of 280 × 220 and the popover default of 560 × 420;
- keeps the panel on screen with a 16 pt margin.

With no `panelSize`, the panel is 560 × 420. A new `panelSize` while the panel is open resizes it, animated unless Reduce Motion is on.

## Lifecycle

- **Approval.** macOS lists a plugin from a separate app as waiting until the person turns it on in the system window: DOKK Settings › Plugins › Manage Plugins…. DOKK can count waiting plugins but cannot name them.
- **Auto-pin.** The first time DOKK sees a plugin enabled, it pins its tile at the end of the plugin section. An unpinned plugin stays unpinned when it is turned off and on again.
- **Running.** A pinned plugin runs for as long as its tile is pinned. The panel opening and closing changes only the panel's scene; closing the panel ends that scene.
- **Ending.** Unpinning, turning the plugin off, or uninstalling it ends DOKK's session. DOKK sends `willDisconnect` first, then invalidates the connection and its `AppExtensionProcess`. The spike saw plugin processes outlive every host reference by minutes, so **exit when DOKK's last connection closes**. `DOKKPluginHostLink` does this after three seconds unless DOKK reconnects.
- **Stopped.** If the process exits on its own, or sends no tile state within 15 seconds:
  - the tile turns grey with a restart chip, and its badge hides;
  - the panel shows "stopped · Restart" in place.
  
  Restart launches a fresh process. Persist anything the tile should show after a restart, or derive it again at launch.
- **Discovery.** A running DOKK sees approvals at once. Installs are rechecked when DOKK comes to the front and when the Plugins page opens, because macOS does not report them to a running monitor.

## Distribution

- A plugin from another developer is discovered and offered for approval. Loading it after approval has not been checked yet.
- DOKK sets no team or code requirement on its extension point.
- Whether a Mac App Store app (philos) may ship an extension for a third-party extension point is open. Benn is checking that with a TestFlight build.

## How the extension point is declared

`Configuration/DOKKPluginExtensionPoint.appexpt` declares the point. It is a static ExtensionKit plist that the DeeDock target's "Embed Extension Point" phase copies into `DOKK.app/Contents/Extensions`. Findings on macOS 27.0 that led there:

- `@AppExtensionPoint.Definition` names a point `<host bundle identifier>.<name>`. DOKK (`de.benjaminkraatz.DeeDock`) and DOKK Dev (`de.benjaminkraatz.DeeDock.dev`) would get two separate points, as in the spike.
- LaunchServices reads an app's points only from `Contents/Extensions`. A file in `Contents/Resources` was ignored.
- LaunchServices registers a third-party point only when its identifier starts with the declaring app's bundle identifier. A copy of DOKK Dev declaring `de.benjaminkraatz.DeeDock.plugin` was not registered; the same file with `de.benjaminkraatz.DeeDock.dev.probeplugin` was. Apple's own services declare unprefixed points, such as `com.apple.crash-reporter.extension`, but that exemption is Apple's.
- Two apps can declare the same identifier. Two probe copies with bundle IDs `X` and `X.dev` both declaring `X.dev.plugin` were both registered, each with its own parent.

So the one shared identifier has to start with DOKK Dev's bundle ID, which also starts with DOKK's: `de.benjaminkraatz.DeeDock.dev.plugin`. It equals the point DOKK Dev declared in the spike. Every probe ran against build products in a scratch folder. They were unregistered afterwards, and DOKK was never launched.

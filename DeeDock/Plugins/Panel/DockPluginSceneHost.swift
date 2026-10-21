import AppKit
import ExtensionFoundation
import ExtensionKit
import SwiftUI

/// The plugin's own panel scene, drawn by the plugin's process and shown inside DOKK's panel.
///
/// `EXHostViewController` renders the remote SwiftUI as a remote view. The scene fills whatever
/// SwiftUI proposes; the panel's size comes from ``DockPluginPanelGeometry``, never from the remote
/// content. Raising `generation` reloads the scene, which is how a restart brings it back.
/// Removing the view clears the configuration, which ends the scene.
struct DockPluginSceneHost: NSViewControllerRepresentable {
    let identity: AppExtensionIdentity
    let generation: Int
    /// Called when the scene ends with an error, such as the plugin process exiting. ExtensionKit
    /// can report one exit twice, so the receiver must tolerate repeats.
    let failed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(failed: failed) }

    func makeNSViewController(context: Context) -> EXHostViewController {
        let controller = EXHostViewController()
        controller.placeholderView = DockPluginScenePlaceholder()
        controller.delegate = context.coordinator
        controller.configuration = configuration
        context.coordinator.generation = generation
        return controller
    }

    func updateNSViewController(_ controller: EXHostViewController, context: Context) {
        context.coordinator.failed = failed
        guard context.coordinator.generation != generation else { return }
        context.coordinator.generation = generation
        controller.configuration = nil
        controller.configuration = configuration
    }

    static func dismantleNSViewController(_ controller: EXHostViewController, coordinator: Coordinator) {
        controller.delegate = nil
        controller.configuration = nil
    }

    /// Fills the proposal. The remote view's own fitting size is a placeholder's until the scene
    /// draws, and letting it win shrank the spike's panel to 16 points.
    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: EXHostViewController,
                      context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 280, height: 170))
    }

    private var configuration: EXHostViewController.Configuration {
        EXHostViewController.Configuration(appExtension: identity, sceneID: DOKKPluginContract.panelSceneID)
    }

    final class Coordinator: NSObject, EXHostViewControllerDelegate {
        var failed: () -> Void
        var generation = 0

        init(failed: @escaping () -> Void) { self.failed = failed }

        func hostViewControllerDidActivate(_ viewController: EXHostViewController) {}

        func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: (any Error)?) {
            guard error != nil else { return }
            failed()
        }
    }
}

/// What the scene shows until the plugin's first frame arrives: a small spinner in the middle.
///
/// Every hugging priority is low so the placeholder never sizes the panel.
private final class DockPluginScenePlaceholder: NSView {
    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(.defaultLow, for: orientation)
            setContentCompressionResistancePriority(.defaultLow, for: orientation)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel(String(localized: .pluginPanelLoading))
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Starts and stops with visibility, so no animation runs behind a hidden placeholder.
        if window == nil { spinner.stopAnimation(nil) } else { spinner.startAnimation(nil) }
    }
}

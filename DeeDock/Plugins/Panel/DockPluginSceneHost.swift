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
        // Tearing down the old scene can report its earlier failure again; only the new one counts.
        context.coordinator.awaitingActivation = true
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
        /// True from a reload until the new scene activates.
        var awaitingActivation = false

        init(failed: @escaping () -> Void) { self.failed = failed }

        func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
            awaitingActivation = false
        }

        func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: (any Error)?) {
            guard error != nil, !awaitingActivation else { return }
            failed()
        }
    }
}

/// What the scene shows until the plugin's first frame arrives: a small spinner in the middle.
///
/// The spinner waits a beat before it appears, so a plugin that draws within a few hundred
/// milliseconds never flashes one. Every hugging priority is low so the placeholder never sizes
/// the panel.
private final class DockPluginScenePlaceholder: NSView {
    private let spinner = NSProgressIndicator()
    /// Pending reveal, cancelled when the placeholder leaves its window first.
    private var reveal: Task<Void, Never>?
    private static let revealDelay: Duration = .milliseconds(300)

    init() {
        super.init(frame: .zero)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.alphaValue = 0
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
        reveal?.cancel()
        reveal = nil
        guard window != nil else {
            spinner.stopAnimation(nil)
            spinner.alphaValue = 0
            return
        }
        spinner.startAnimation(nil)
        // `@MainActor` spelled out: a `[weak self]` capture stops the task inheriting the view's
        // isolation on its own.
        reveal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled, let self, window != nil else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.1 : 0.2
            spinner.animator().alphaValue = 1
            NSAnimationContext.endGrouping()
        }
    }
}

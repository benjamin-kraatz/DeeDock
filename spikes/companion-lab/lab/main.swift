import AppKit

// Throwaway spike. Run from a shell whose host already holds Accessibility + Screen Recording,
// so TCC attributes the lab to that host and never prompts.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = MainActor.assumeIsolated { CompanionController() }
MainActor.assumeIsolated { controller.start() }
application.run()

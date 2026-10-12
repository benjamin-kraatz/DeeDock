import SwiftUI

/// Onboarding's card at one step, over a Hub-sized backdrop with the veil, for previews. The coordinator is
/// `LookoutSetupCoordinator.preview`: an inert engine and downloader, a stub inspector and picker, so nothing reads a
/// folder, downloads, asks macOS for access or opens a panel.
struct LookoutSetupSheetPreview: View {
    let reduceMotion: Bool
    let reduceTransparency: Bool

    @State private var setup: LookoutSetupCoordinator

    init(step: LookoutSetupStep, download: LookoutModelDownloader.FileState = .waiting, reduceMotion: Bool = false,
         reduceTransparency: Bool = false, configure: (inout LookoutSetupDraft) -> Void = { _ in }) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        _setup = State(initialValue: .preview(step: step, download: download, configure: configure))
    }

    var body: some View {
        LookoutSetupOverlay(setup: setup, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            .frame(width: HubStyle.anchoredSize.width, height: HubStyle.anchoredSize.height)
            .background {
                LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(.regularMaterial)
            }
    }
}

#Preview("Overlay · Reduce Motion and Reduce Transparency") {
    LookoutSetupSheetPreview(step: .folders, reduceMotion: true, reduceTransparency: true)
}

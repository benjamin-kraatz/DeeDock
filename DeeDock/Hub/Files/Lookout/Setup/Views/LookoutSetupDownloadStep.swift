import SwiftUI

/// Step 4: the model's two files with their progress, "Checking…" while each checksum is verified, then Ready; the
/// battery choice; and that closing onboarding doesn't stop the download.
struct LookoutSetupDownloadStep: View {
    let downloader: LookoutModelDownloader
    let indexOnBattery: Bool
    let setIndexOnBattery: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LookoutSetupHeading(title: .lookoutSetupDownloadTitle, lead: .lookoutSetupDownloadLead)
            ForEach(downloader.files, id: \.name) { file in
                LookoutSetupDownloadRow(file: file, state: downloader.states[file.name] ?? .waiting,
                                        fraction: downloader.fraction(of: file))
            }
            if let error = downloader.error {
                LookoutSetupDownloadFailure(message: error.message) { downloader.start() }
            }
            LookoutSetupBatteryToggle(isOn: indexOnBattery, set: setIndexOnBattery)
            Text(.lookoutSetupDownloadBackground)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }
}

/// One model file: what it's for, its size, and its progress (the mockup's `.dl`).
private struct LookoutSetupDownloadRow: View {
    let file: ModelFiles.File
    let state: LookoutModelDownloader.FileState
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                status
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
            LookoutSetupProgressBar(fraction: fraction)
                .padding(.top, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .lookoutSetupRow(radius: 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var isWords: Bool { file.name == ModelFiles.text.name }

    /// "Words · 310 MB", the size in the secondary style.
    private var title: AttributedString {
        var text = AttributedString(localized: isWords ? .lookoutSetupDownloadWords : .lookoutSetupDownloadPictures)
        var size = AttributedString(" · " + file.bytes.formatted(.byteCount(style: .file)))
        size.foregroundColor = .secondary
        size.font = .system(size: 12)
        text += size
        return text
    }

    private var detail: LocalizedStringResource {
        isWords ? .lookoutSetupDownloadWordsDetail : .lookoutSetupDownloadPicturesDetail
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .ready:
            Text(.lookoutSetupReady).foregroundStyle(LookoutTheme.ready)
        case .verifying:
            Text(.lookoutSetupChecking).foregroundStyle(.secondary)
        case .waiting, .downloading:
            Text(fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
        }
    }
}

/// The 4 pt bar, the Lookout accent over the chip track (the mockup's `.bar`).
struct LookoutSetupProgressBar: View {
    let fraction: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .fill(HubFilesTheme(scheme).chipHighlight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LookoutTheme(scheme).accent)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
            .animation(HubFilesMotion.animation(.easeOut(duration: 0.3)), value: fraction)
            .accessibilityHidden(true)
    }
}

/// Why the download stopped, and Try Again.
private struct LookoutSetupDownloadFailure: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: message)
                .font(.system(size: 12))
                .foregroundStyle(LookoutTheme.paused)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(.lookoutSetupTryAgain, action: retry)
                .buttonStyle(.lookoutMini)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// "Read files on battery too", the switch before its label as in the mockup (`.tog`). The small switch is the
/// mockup's 32 × 19 and the size Lookout's Settings section uses.
private struct LookoutSetupBatteryToggle: View {
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isOn }, set: set)) { Text(.lookoutBatteryTitle) }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(LookoutTheme.ready)
            VStack(alignment: .leading, spacing: 2) {
                Text(.lookoutBatteryTitle)
                    .font(.system(size: 12.5))
                Text(.lookoutBatteryDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

#Preview("Download · in progress") {
    LookoutSetupSheetPreview(step: .download, download: .downloading(received: 140_000_000))
        .preferredColorScheme(.dark)
}

#Preview("Download · ready, light") {
    LookoutSetupSheetPreview(step: .download, download: .ready)
        .preferredColorScheme(.light)
}

#Preview("Download · checking, German") {
    LookoutSetupSheetPreview(step: .download, download: .verifying)
        .environment(\.locale, Locale(identifier: "de"))
}

import SwiftUI

/// The top of a labelling question: the app's icon, "Is <App> behaving as expected?", the reason line under the
/// feature's glyph, and the trailing "…" menu and close button. While the question can expire, the close button
/// wears the expiry ring.
struct AppHealthQuestionHeader: View {
    let app: AppHealthAppDisplay
    /// Nil for manual labels, which explain nothing.
    let reason: String?
    /// Nil once the question no longer expires, or never did.
    var expiry: AppHealthLabelSession.Expiry?
    /// The "…" menu's commands; nil hides the menu (manual labels).
    let perform: ((AppHealthLabelSession.MenuCommand) -> Void)?
    let close: () -> Void
    var reduceMotion = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppHealthAppIcon(icon: app.icon, size: 36)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(.appHealthPromptQuestion(app: app.name))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let reason {
                    AppHealthReasonLine(reason: reason)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                if let perform { AppHealthPromptMoreMenu(perform: perform, reduceMotion: reduceMotion) }
                AppHealthPromptCloseButton(expiry: expiry, reduceMotion: reduceMotion, action: close)
            }
            .padding(.top, -2)
        }
    }
}

/// The one-line reason under the question, after the feature's glyph in the tint so the question's origin is clear.
struct AppHealthReasonLine: View {
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "waveform.path.ecg")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(verbatim: reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An app icon from macOS, or a neutral placeholder when the app is gone.
struct AppHealthAppIcon: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "…": Don't ask about this app, Pause labelling for today.
struct AppHealthPromptMoreMenu: View {
    let perform: (AppHealthLabelSession.MenuCommand) -> Void
    var reduceMotion = false

    var body: some View {
        Menu {
            Button(.appHealthDontAskApp) { perform(.dontAsk) }
            Button(.appHealthPauseToday) { perform(.pauseToday) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(AppHealthIconButtonStyle(reduceMotion: reduceMotion))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.appHealthPromptMore))
        .accessibilityHint(Text(.appHealthPromptMoreHint))
    }
}

/// Closes the question without an answer. Carries the expiry ring while the question can still expire.
struct AppHealthPromptCloseButton: View {
    var expiry: AppHealthLabelSession.Expiry?
    var reduceMotion = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(AppHealthIconButtonStyle(reduceMotion: reduceMotion))
        .overlay {
            if let expiry {
                AppHealthExpiryRing(expiry: expiry)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: expiry == nil)
        .accessibilityLabel(Text(.appHealthPromptClose))
        .accessibilityHint(Text(.appHealthPromptCloseHint))
    }
}

#if DEBUG
#Preview("Header, expiring") {
    VStack(alignment: .leading, spacing: 20) {
        AppHealthQuestionHeader(app: AppHealthLabellingPreviewData.app,
                                reason: AppHealthLabellingPreviewData.reason([.cpu, .background]),
                                expiry: AppHealthLabelSession.Expiry(fraction: 0.6, secondsLeft: nil),
                                perform: { _ in }, close: {})
        AppHealthQuestionHeader(app: AppHealthLabellingPreviewData.longNamedApp, reason: nil, perform: nil, close: {})
    }
    .tint(SettingsPage.appHealth.tint)
    .padding(16)
    .frame(width: AppHealthPromptView.width)
    .appHealthSurface(opaque: false)
    .padding()
}
#endif

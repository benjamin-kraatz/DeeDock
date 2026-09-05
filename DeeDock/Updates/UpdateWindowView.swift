#if DIRECT_DISTRIBUTION
import SwiftUI

/// DeeDock's update window composition. Rendering never starts a check or acknowledges a callback.
struct UpdateWindowView: View {
    let presentation: UpdatePresentation
    var icon: NSImage? = nil
    var action: (UpdateAction, UUID) -> Void = { _, _ in }
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tint: Color { presentation.phase == .failed ? .orange : .indigo }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    UpdateWindowHeader(presentation: presentation, icon: icon, tint: tint)
                    UpdateWindowDetails(presentation: presentation)
                }
                .padding(.horizontal, 32)
                .padding(.top, 42)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            UpdateWindowActions(presentation: presentation, action: action)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            LinearGradient(colors: [tint.opacity(reduceTransparency ? 0 : 0.10), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 170)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .tint(tint)
        .onExitCommand(perform: close)
        .environment(\.openURL, OpenURLAction { url in
            UpdateReleaseNotes.safeLink(url) == nil ? .discarded : .systemAction(url)
        })
    }
}

/// Brand and phase are separate from progress, so small byte changes do not replace the header.
private struct UpdateWindowHeader: View {
    let presentation: UpdatePresentation
    let icon: NSImage?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Group {
                    if let icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "dock.rectangle").resizable().scaledToFit().padding(12) }
                }
                .frame(width: 70, height: 70)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(.appName).font(.headline)
                    Text(.updatesWindowTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: presentation.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(presentation.title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Each action is tied to the callback generation that produced this footer.
private struct UpdateWindowActions: View {
    let presentation: UpdatePresentation
    let action: (UpdateAction, UUID) -> Void

    var body: some View {
        let token = presentation.actionToken
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                buttons(token: token)
            }
            VStack(alignment: .trailing, spacing: 12) { buttons(token: token) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .controlSize(.large)
    }

    @ViewBuilder private func buttons(token: UUID) -> some View {
        ForEach(presentation.actions, id: \.self) { item in
            if item == presentation.actions.last {
                Button(presentation.title(for: item)) { action(item, token) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(presentation.title(for: item)) { action(item, token) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

#Preview("Download, German") {
    let model = UpdatePresentation()
    model.phase = .downloading
    model.receivedBytes = 18_000_000
    model.expectedBytes = 42_000_000
    return UpdateWindowView(presentation: model)
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 580, height: 600)
}

#Preview("Update ready") {
    let model = UpdatePresentation()
    model.phase = .ready
    return UpdateWindowView(presentation: model).frame(width: 580, height: 600)
}

#Preview("Release notes") {
    let model = UpdatePresentation()
    model.phase = .available
    model.offer = UpdateOffer(version: "0.2.0", stage: .notDownloaded, critical: false, major: false,
                              informational: false, informationURL: nil, releaseNotesURL: nil)
    model.notes = [
        UpdateReleaseNoteBlock(id: 0, style: .heading(2), text: AttributedString("A quieter dock.")),
        UpdateReleaseNoteBlock(id: 1, text: AttributedString("Improved display placement across multiple monitors."), marker: "•"),
        UpdateReleaseNoteBlock(id: 2, text: AttributedString("More precise activation zones"), marker: "•")
    ]
    return UpdateWindowView(presentation: model).frame(width: 580, height: 600)
}

#Preview("Permission") {
    let model = UpdatePresentation()
    model.phase = .permission
    return UpdateWindowView(presentation: model).frame(width: 580, height: 600)
}

#Preview("Error") {
    let model = UpdatePresentation()
    model.phase = .failed
    return UpdateWindowView(presentation: model).frame(width: 580, height: 600)
}
#endif

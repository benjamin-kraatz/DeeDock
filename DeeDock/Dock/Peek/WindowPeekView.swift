import SwiftUI

struct WindowPeekView: View {
    let state: WindowPeekState
    let keyboard: Bool
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var usesOpaqueBackground: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: state.appIcon).resizable().interpolation(.high).frame(width: 24, height: 24)
                Text(verbatim: state.appName).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(12)
        .background(usesOpaqueBackground ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                         : AnyShapeStyle(.regularMaterial),
                    in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.7), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 7)
        .padding(6)
        .onHover { state.hovered?($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.windowPeekAccessibilityLabel(appName: state.appName)))
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .loading:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text(.windowPeekLoading) }
                .frame(maxWidth: .infinity, minHeight: 72)
        case .windows:
            VStack(alignment: .leading, spacing: 8) {
                cards
                if state.usesApplicationSelection {
                    Text(.windowPeekApplicationSelectionHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .appFallback:
            fallback(message: .windowPeekWindowAccessFallback, settings: true)
        case .discoveryFailed(let failure):
            fallback(message: failure.peekMessage, settings: true)
        case .noWindows:
            fallback(message: .windowPeekNoWindows, settings: false)
        case .noMatch:
            VStack(alignment: .leading, spacing: 10) {
                Text(.windowPeekNoMatch).foregroundStyle(.secondary)
                HStack {
                    Button(.windowPeekShowApp) { state.showApp?() }
                    Button(.windowPeekShowAll) { state.showAll?() }
                }
            }
        }
    }

    @ViewBuilder private var cards: some View {
        let cardSize = WindowPeekGeometry.cardSize(state.settings)
        switch state.settings.windowPeekLayout {
        case .list:
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) { cardRows(size: cardSize) }
            }.scrollIndicators(.hidden)
        case .grid:
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cardSize.width), spacing: 10)], spacing: 10) {
                    cardRows(size: cardSize)
                }
            }.scrollIndicators(.hidden)
        case .filmstrip:
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) { cardRows(size: cardSize) }
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func cardRows(size: CGSize) -> some View {
        ForEach(state.cards) { card in
            WindowPeekCardView(card: card, appIcon: state.appIcon, settings: state.settings,
                               selected: keyboard && state.selectedID == card.id) {
                state.choose?(card.id)
            }
            .frame(width: size.width, height: size.height)
            .onAppear { state.thumbnailNeeded?(card.id) }
        }
    }

    private func fallback(message: LocalizedStringResource, settings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(.windowPeekShowApp) { state.showApp?() }
                if settings {
                    SettingsLink {
                        Text(.windowPeekOpenSettings)
                    }
                    .simultaneousGesture(TapGesture().onEnded { state.settingsSelected?() })
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}

private extension ApplicationWindowDiscoveryFailure {
    var peekMessage: LocalizedStringResource {
        switch self {
        case .sandboxRestricted: .windowPeekSandboxFallback
        case .permissionRequired: .windowPeekWindowAccessFallback
        case .applicationUnavailable, .windowUnavailable, .accessibility, .unknown:
            .windowPeekDiscoveryFailed
        }
    }
}

private struct WindowPeekCardView: View {
    let card: WindowPeekCard
    let appIcon: NSImage
    let settings: DockSettings
    let selected: Bool
    let action: () -> Void

    private var title: String {
        ApplicationContextMenuProjection.windowTitle(card.window, untitled: String(localized: .applicationMenuUntitledWindow))
    }

    var body: some View {
        Button(action: action) {
            if settings.windowPeekLayout == .list {
                HStack(spacing: 10) { artwork; caption.frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                VStack(alignment: .leading, spacing: settings.windowPeekStyle == .captioned ? 8 : 5) {
                    artwork
                    if settings.windowPeekStyle != .minimal { caption }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(settings.windowPeekStyle == .glass ? 7 : 3)
        .background(settings.windowPeekStyle == .glass ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .accessibilityLabel(Text(.applicationMenuOpenWindow(title: title)))
        .accessibilityValue(card.window.isMinimized ? Text(.windowPeekMinimized) : Text(verbatim: ""))
    }

    private var artwork: some View {
        Group {
            if let thumbnail = card.thumbnail {
                Image(decorative: thumbnail, scale: 2).resizable().interpolation(.high).scaledToFit()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.55))
                    Image(nsImage: appIcon).resizable().interpolation(.high).scaledToFit().padding(22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.06))
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 7))
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(.callout.weight(.medium)).lineLimit(2)
            if card.window.isMinimized {
                Label { Text(.windowPeekMinimized) } icon: { Image(systemName: "minus.square") }
                    .font(.caption).foregroundStyle(.secondary)
            } else if card.window.isMain {
                Label { Text(.windowPeekMainWindow) } icon: { Image(systemName: "checkmark.circle") }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
@MainActor private func windowPeekPreviewState(
    preset: WindowPeekPreset = .balanced,
    phase: WindowPeekPhase = .windows,
    longText: Bool = false
) -> WindowPeekState {
    var settings = DockSettings.defaults
    preset.apply(to: &settings)
    let item = longText ? DockPreviewData.longNameItems[0] : DockPreviewData.items[0]
    let state = WindowPeekState(item: item, settings: settings)
    state.phase = phase
    if phase == .windows {
        let session = UUID()
        state.cards = (0..<4).map { index in
            WindowPeekCard(window: ApplicationWindowSummary(
                token: ApplicationWindowToken(sessionID: session, id: UUID()),
                processIdentifier: 42,
                title: longText && index == 0
                    ? "A document window with a deliberately long localized title for layout inspection"
                    : "Document \(index + 1)",
                frame: CGRect(x: index * 20, y: index * 20, width: 960, height: 600),
                isMinimized: index == 2,
                isMain: index == 0
            ), thumbnail: nil)
        }
        state.selectedID = state.cards.first?.id
    }
    return state
}

#Preview("Compact · Small · List · Minimal") {
    WindowPeekView(state: windowPeekPreviewState(preset: .compact), keyboard: false)
        .frame(width: 440, height: 480)
}
#Preview("Balanced · Medium · Grid · Glass") {
    WindowPeekView(state: windowPeekPreviewState(), keyboard: true)
        .frame(width: 790, height: 520)
}
#Preview("Showcase · Large · Filmstrip · Captioned") {
    WindowPeekView(state: windowPeekPreviewState(preset: .showcase), keyboard: false)
        .frame(width: 900, height: 330)
}
#Preview("Fallbacks and long text") {
    WindowPeekView(state: windowPeekPreviewState(phase: .appFallback, longText: true), keyboard: false)
        .frame(width: 500, height: 220)
}
#Preview("Sandbox-restricted window access") {
    WindowPeekView(state: windowPeekPreviewState(phase: .discoveryFailed(.sandboxRestricted)), keyboard: false)
        .frame(width: 500, height: 220)
}
#Preview("No windows match") {
    WindowPeekView(state: windowPeekPreviewState(phase: .noMatch), keyboard: false)
        .frame(width: 400, height: 190)
}
#Preview("Reduce Transparency") {
    WindowPeekView(state: windowPeekPreviewState(), keyboard: false, reduceTransparencyOverride: true)
        .frame(width: 790, height: 520)
}
#endif

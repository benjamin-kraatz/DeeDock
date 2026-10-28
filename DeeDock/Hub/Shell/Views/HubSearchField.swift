import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The header search field, bound to the visible tab's query and prompt.
///
/// Focus is driven from AppKit through request counters on ``HubShellState`` (⌘F, opening on a
/// tab, a tab's `focusSearchField()`), and the field reports its own focus back so the key monitor
/// can tell tabs whether an event was typed into it.
///
/// A tab with `extras` (Files) can put a token before the text (the picture searched with) and turn the field into
/// a drop well while something is dragged over the Hub: it widens by 90 pt with the Hub's spring and says what
/// dropping does (`HubSearchDropState`). The text field stays in place underneath, hidden, so a field that has focus
/// keeps it through a drag.
struct HubSearchField: View {
    @Binding var query: String
    let prompt: LocalizedStringResource
    let state: HubShellState
    var extras: (any HubSearchExtras)?

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// How much wider the field grows as a drop well (the mockup's 300 → 390 pt).
    static let wellGrowth: CGFloat = 90

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let token = extras?.searchToken
        let drop = extras?.searchDropState ?? .none
        let targeted = extras?.isSearchDropTargeted ?? false
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(wellTint(drop).map(AnyShapeStyle.init) ?? AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    if let token, let extras {
                        HubSearchTokenView(token: token, reduceMotion: state.reduceMotion, compact: !query.isEmpty) {
                            extras.removeSearchToken()
                            state.requestSearchFocus()
                        }
                        .id(token.id)
                        .animation(state.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
                                   value: query.isEmpty)
                    }
                    textField(token: token)
                    if !query.isEmpty || token != nil {
                        clearButton
                    }
                }
                .opacity(drop.isShown ? 0 : 1)
                .allowsHitTesting(!drop.isShown)
                if let message = wellMessage(drop) {
                    Text(verbatim: message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(wellTint(drop) ?? .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .frame(width: HubStyle.searchFieldWidth + (drop.isShown ? Self.wellGrowth : 0), height: 34)
        .background(fill(drop), in: shape)
        .overlay { shape.strokeBorder(stroke(drop), lineWidth: strokeWidth(drop, targeted: targeted)) }
        .overlay {
            HubSearchWellHalo(shape: shape, drop: drop, targeted: targeted, reduceMotion: state.reduceMotion)
        }
        // The mockup's focus ring: a soft 3 pt accent halo outside the field.
        .overlay {
            shape
                .inset(by: -2)
                .strokeBorder(Color.accentColor.opacity(focused && !drop.isShown ? 0.4 : 0), lineWidth: 3)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.2), value: focused)
        .animation(.easeOut(duration: 0.15), value: query.isEmpty)
        .animation(state.reduceMotion ? .easeOut(duration: 0.15)
                   : .spring(response: 0.32, dampingFraction: 0.72), value: drop)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .contentShape(shape)
        .onTapGesture { focused = true }
        .modifier(HubSearchFieldDrop(extras: extras))
        .onChange(of: state.searchFocusRequest) {
            focused = true
            guard state.searchFocusPlacesCaretAtEnd else { return }
            // AppKit selects a text field's contents when it becomes first responder. Collapse the
            // selection on the next turn, once the field editor exists, so type-to-search appends.
            DispatchQueue.main.async {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
        .onChange(of: state.contentFocusRequest) { focused = false }
        .onChange(of: focused) { _, value in state.searchFieldFocused = value }
    }

    /// The text field. Beside a token it has no placeholder (there's no room for one), and its VoiceOver label says
    /// that words typed there search together with the token's picture.
    private func textField(token: HubSearchToken?) -> some View {
        let label = token != nil ? extras?.searchTokenPrompt ?? prompt : prompt
        return TextField(text: $query, prompt: token == nil ? Text(prompt) : Text(verbatim: "")) {
            Text(label)
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13.5))
        .focused($focused)
    }

    private var clearButton: some View {
        Button {
            if extras?.searchToken != nil { extras?.clearSearchWithToken() } else { query = "" }
            state.requestSearchFocus()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(Text(.hubSearchClear))
        .accessibilityLabel(Text(.hubSearchClear))
        .transition(.opacity)
    }

    // MARK: Drop well

    private func wellMessage(_ drop: HubSearchDropState) -> String? {
        switch drop {
        case .none: nil
        case .accepting(let message), .refusing(let message): message
        }
    }

    private func wellTint(_ drop: HubSearchDropState) -> Color? {
        switch drop {
        case .none: nil
        case .accepting: LookoutTheme(colorScheme).accent
        case .refusing: LookoutTheme.paused
        }
    }

    private func fill(_ drop: HubSearchDropState) -> Color {
        switch drop {
        case .none: Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.05)
        case .accepting: LookoutTheme(colorScheme).accentSoft
        case .refusing: LookoutTheme.paused.opacity(0.10)
        }
    }

    private func stroke(_ drop: HubSearchDropState) -> Color {
        wellTint(drop) ?? Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.075)
    }

    private func strokeWidth(_ drop: HubSearchDropState, targeted: Bool) -> CGFloat {
        switch drop {
        case .none: 0.5
        case .accepting: targeted ? 2 : 1.5
        case .refusing: 1.5
        }
    }
}

/// The soft ring around an accepting drop well (the mockup's `0 0 0 4px var(--lookSoft)`): it breathes between 4 and
/// 7 pt every 1.4 s while the drag is elsewhere over the Hub, and holds wide with a glow once it's over the field.
/// Reduce Motion keeps it still.
private struct HubSearchWellHalo<S: InsettableShape>: View {
    let shape: S
    let drop: HubSearchDropState
    let targeted: Bool
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let soft = LookoutTheme(scheme).accentSoft
        if case .accepting = drop {
            if targeted || reduceMotion {
                shape.inset(by: targeted ? -6 : -4)
                    .strokeBorder(soft, lineWidth: targeted ? 6 : 4)
                    .shadow(color: soft, radius: targeted ? 11 : 0)
                    .allowsHitTesting(false)
            } else {
                PhaseAnimator([false, true]) { wide in
                    shape.inset(by: wide ? -7 : -4)
                        .strokeBorder(soft, lineWidth: wide ? 7 : 4)
                } animation: { _ in .easeInOut(duration: 0.7) }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Makes the field a drop target only for a tab that takes drops on it. Like the Hub's drag observer, the modifier
/// stays attached and registers no types without extras, so switching tabs never rebuilds the field.
private struct HubSearchFieldDrop: ViewModifier {
    let extras: (any HubSearchExtras)?

    func body(content: Content) -> some View {
        content.onDrop(of: extras?.searchDropTypes ?? [], delegate: HubSearchFieldDropDelegate(extras: extras))
    }
}

/// Fixed search extras for previews: a token, or a drop well in one state. Never reads a pasteboard.
@MainActor
private final class HubSearchExtrasPreviewStub: HubSearchExtras {
    let searchToken: HubSearchToken?
    let searchDropState: HubSearchDropState
    let isSearchDropTargeted: Bool

    init(token: String? = nil, drop: HubSearchDropState = .none, targeted: Bool = false) {
        searchToken = token.map { HubSearchToken(id: UUID(), title: $0, fileURL: nil, image: nil,
                                                 accessibilityLabel: $0) }
        searchDropState = drop
        isSearchDropTargeted = targeted
    }

    var searchTokenPrompt: LocalizedStringResource { .lookoutPicturePrompt }
    var searchDropTypes: [UTType] { [.fileURL, .image] }
    var searchFieldAcceptsDrag: Bool { false }
    func removeSearchToken() {}
    func clearSearchWithToken() {}
    func hubDragChanged(inside: Bool) {}
    func searchFieldDragTargeted(_ targeted: Bool) {}
    func searchFieldPerformDrop() -> Bool { false }
}

#Preview("Search field · picture and drop well") {
    @Previewable @State var empty = ""
    let accepting = HubSearchDropState.accepting(message: String(localized: .lookoutPictureDropHere))
    let refusing = HubSearchDropState.refusing(message: String(localized: .lookoutPictureDropRefused))
    VStack(alignment: .trailing, spacing: 18) {
        HubSearchField(query: $empty, prompt: .hubTabFiles, state: .preview(tab: .files),
                       extras: HubSearchExtrasPreviewStub(token: "IMG_5012.HEIC"))
        HubSearchField(query: $empty, prompt: .hubTabFiles, state: .preview(tab: .files),
                       extras: HubSearchExtrasPreviewStub(drop: accepting))
        HubSearchField(query: $empty, prompt: .hubTabFiles, state: .preview(tab: .files),
                       extras: HubSearchExtrasPreviewStub(drop: accepting, targeted: true))
        HubSearchField(query: $empty, prompt: .hubTabFiles, state: .preview(tab: .files),
                       extras: HubSearchExtrasPreviewStub(drop: refusing))
    }
    .padding(24)
    .frame(width: 460)
    .background(.regularMaterial)
}

#Preview("Search field") {
    @Previewable @State var query = ""
    @Previewable @State var filled = "Downloads"
    VStack(spacing: 16) {
        HubSearchField(query: $query, prompt: .hubTabFiles, state: HubShellState(tab: .files))
        HubSearchField(query: $filled, prompt: .hubTabFiles, state: HubShellState(tab: .files))
    }
    .padding(24)
}

import SwiftUI

/// One exhibit hung on a lit wall: the framed piece, its placard, and the actions for it.
///
/// Revealed content of a redacted exhibit lives only in this view's state. Selecting another
/// exhibit, pressing Hide, or closing the window drops it.
struct ClipboardExhibitDetail: View {
    let exhibit: ClipboardExhibit
    @Binding var renaming: ClipboardExhibit.ID?
    let actions: ClipboardMuseumActions

    @Environment(\.colorScheme) private var colorScheme
    @State private var status: ClipboardDetailStatus?
    @State private var confirmsRedact = false
    @State private var confirmsShred = false
    @State private var revealed: ClipboardVeiledPayload?
    @State private var authenticating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                ClipboardExhibitFrame {
                    ClipboardExhibitArtwork(exhibit: exhibit, imageURL: actions.imageURL(exhibit), revealed: revealed)
                }
                .animation(.smooth(duration: 0.45), value: revealed != nil)
                ClipboardExhibitPlacard(exhibit: exhibit, revealed: revealed != nil,
                                        isRenaming: Binding(get: { renaming == exhibit.id },
                                                            set: { renaming = $0 ? exhibit.id : nil }),
                                        rename: { actions.rename(exhibit.id, $0) })
                ClipboardExhibitActionBar(exhibit: exhibit, revealed: revealed, authenticating: authenticating,
                                          copy: { status = actions.restore(exhibit, revealed) ? .copied : .copyFailed },
                                          save: { format in
                                              actions.save(exhibit, format, revealed) { ok in if !ok { status = .saveFailed } }
                                          },
                                          redact: { confirmsRedact = true },
                                          reveal: reveal, hide: { revealed = nil },
                                          notSecret: notSecret, shred: { confirmsShred = true },
                                          remove: { actions.remove(exhibit.id) })
                ClipboardDetailStatusLine(status: status)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background {
            // A soft pool of light above the piece, the way a gallery spot falls on a wall.
            ZStack {
                ClipboardMuseumPalette.wall(colorScheme)
                RadialGradient(colors: [ClipboardMuseumPalette.spotlight(colorScheme).opacity(0.9), .clear],
                               center: UnitPoint(x: 0.5, y: 0.05), startRadius: 20, endRadius: 520)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(Text(.clipboardMuseumRedactConfirm), isPresented: $confirmsRedact) {
            Button(role: .destructive) { actions.redact(exhibit.id) } label: { Text(.clipboardMuseumRedact) }
        } message: {
            Text(.clipboardMuseumRedactHelp)
        }
        .confirmationDialog(Text(.clipboardMuseumShredConfirm), isPresented: $confirmsShred) {
            Button(role: .destructive) { revealed = nil; actions.shred(exhibit.id) } label: { Text(.clipboardMuseumShred) }
        } message: {
            Text(.clipboardMuseumShredHelp)
        }
        .task(id: status) {
            guard status != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            status = nil
        }
        .onChange(of: exhibit.id) {
            status = nil
            revealed = nil
        }
        .onChange(of: exhibit.isRedacted) { _, redacted in if !redacted { revealed = nil } }
    }

    private func reveal() {
        authenticating = true
        Task {
            let payload = await actions.reveal(exhibit.id)
            authenticating = false
            if let payload { revealed = payload } else { status = .authFailed }
        }
    }

    private func notSecret() {
        authenticating = true
        Task {
            let restored = await actions.unredact(exhibit.id)
            authenticating = false
            if !restored { status = .authFailed }
        }
    }
}

enum ClipboardDetailStatus: Hashable {
    case copied, copyFailed, saveFailed, authFailed
}

/// A one-line result under the actions. Space is reserved so the layout does not jump.
private struct ClipboardDetailStatusLine: View {
    let status: ClipboardDetailStatus?

    var body: some View {
        Group {
            switch status {
            case .copied?: Text(.clipboardMuseumRestored)
            case .copyFailed?: Text(.clipboardMuseumRestoreFailed)
            case .saveFailed?: Text(.clipboardMuseumSaveFailed)
            case .authFailed?: Text(.clipboardMuseumAuthFailed)
            case nil: Text(verbatim: " ")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Actions for the current exhibit. A sealed exhibit trades Copy and Redact for Reveal, Not a
/// Secret, and Shred; once revealed it can also be copied and saved.
private struct ClipboardExhibitActionBar: View {
    let exhibit: ClipboardExhibit
    let revealed: ClipboardVeiledPayload?
    let authenticating: Bool
    let copy: () -> Void
    let save: (ClipboardExportFormat) -> Void
    let redact: () -> Void
    let reveal: () -> Void
    let hide: () -> Void
    let notSecret: () -> Void
    let shred: () -> Void
    let remove: () -> Void

    private var contentAvailable: Bool { !exhibit.isRedacted || revealed != nil }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(spacing: 10) { buttons }
        }
        .controlSize(.large)
        .disabled(authenticating)
    }

    @ViewBuilder private var buttons: some View {
        if exhibit.isSealed {
            if revealed == nil {
                Button(action: reveal) {
                    Label { Text(.clipboardMuseumReveal) } icon: { Image(systemName: "touchid") }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: hide) {
                    Label { Text(.clipboardMuseumHide) } icon: { Image(systemName: "eye.slash") }
                }
            }
        }
        if contentAvailable {
            Button(action: copy) {
                Label { Text(.clipboardMuseumRestore) } icon: { Image(systemName: "doc.on.clipboard") }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            Menu {
                ForEach(ClipboardExportFormat.formats(for: exhibit.kind)) { format in
                    Button { save(format) } label: { Text(format.title) }
                }
            } label: {
                Label { Text(.clipboardMuseumSave) } icon: { Image(systemName: "square.and.arrow.down") }
            }
            .fixedSize()
        }
        if exhibit.isSealed {
            Button(action: notSecret) {
                Label { Text(.clipboardMuseumNotSecret) } icon: { Image(systemName: "checkmark.shield") }
            }
            .help(Text(.clipboardMuseumNotSecretHelp))
            Button(role: .destructive, action: shred) {
                Label { Text(.clipboardMuseumShred) } icon: { Image(systemName: "flame") }
            }
        } else if !exhibit.isRedacted {
            Button(action: redact) {
                Label { Text(.clipboardMuseumRedact) } icon: { Image(systemName: "eye.slash") }
            }
        }
        Button(role: .destructive, action: remove) {
            Label { Text(.clipboardMuseumRemove) } icon: { Image(systemName: "trash") }
        }
    }
}

/// A dark moulding around a paper mat, with a cast shadow onto the wall.
struct ClipboardExhibitFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(30)
            .background(ClipboardMuseumPalette.mat)
            .overlay { Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1).padding(12) }
            .padding(9)
            .background(ClipboardMuseumPalette.moulding)
            .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 14)
    }
}

#if DEBUG
#Preview("Text exhibit") {
    @Previewable @State var renaming: UUID?
    ClipboardExhibitDetail(exhibit: ClipboardExhibit.previewCollection[0], renaming: $renaming, actions: .preview)
        .frame(width: 720, height: 720)
}

#Preview("Sealed token, dark") {
    @Previewable @State var renaming: UUID?
    ClipboardExhibitDetail(exhibit: ClipboardExhibit.previewCollection[2], renaming: $renaming, actions: .preview)
        .frame(width: 720, height: 720)
        .preferredColorScheme(.dark)
}
#endif

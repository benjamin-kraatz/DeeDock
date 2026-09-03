import SwiftUI

struct FolderStackView: View {
    let state: FolderStackState
    let keyboard: Bool
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = FolderStackPanelShape(chrome: state.chrome)
        VStack(spacing: 0) {
            header
            Divider()
            if let error = state.error, !state.entries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(verbatim: error).font(.callout).lineLimit(2)
                    Spacer(minLength: 4)
                    Button(.folderStackRetry) { state.retry() }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.quaternary)
                Divider()
            }
            content
        }
        .padding(.top, state.chrome.edge == .top ? FolderStackGeometry.pointerDepth : 0)
        .padding(.bottom, state.chrome.edge == .bottom ? FolderStackGeometry.pointerDepth : 0)
        .padding(.leading, state.chrome.edge == .left ? FolderStackGeometry.pointerDepth : 0)
        .padding(.trailing, state.chrome.edge == .right ? FolderStackGeometry.pointerDepth : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency || forceOpaqueBackground {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.folderStackAccessibilityLabel(folderName: state.folder.name)))
        .accessibilityValue(Text(.folderStackItemCount(
            count: state.entries.count,
            mode: String(localized: state.presentation == .grid ? .folderStackGrid : .folderStackList)
        )))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").foregroundStyle(.tint).accessibilityHidden(true)
            Text(verbatim: state.folder.name).font(.headline).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                modeButton(.grid, symbol: "square.grid.2x2")
                modeButton(.list, symbol: "list.bullet")
            }
            .padding(2)
            .background(.quaternary, in: .rect(cornerRadius: 7))
            .overlay {
                if state.presentationFocused {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(.tint, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.folderStackPresentationControl))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func modeButton(_ mode: FolderStackPresentation, symbol: String) -> some View {
        Button { state.choose(mode) } label: {
            Image(systemName: symbol).frame(width: 26, height: 22)
                .background(state.presentation == mode ? Color.accentColor.opacity(0.22) : .clear,
                            in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode == .grid ? .folderStackGrid : .folderStackList))
        .accessibilityAddTraits(state.presentation == mode ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        if state.loading && state.entries.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text(.folderStackLoading))
        } else if let error = state.error, state.entries.isEmpty {
            ContentUnavailableView {
                Label(.folderStackUnavailableTitle, systemImage: "folder.badge.questionmark")
            } description: {
                Text(verbatim: error)
            } actions: {
                Button(.folderStackRetry) { state.retry() }
            }
        } else if state.entries.isEmpty {
            ContentUnavailableView(.folderStackEmpty, systemImage: "folder")
        } else if state.presentation == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], spacing: 14) {
                    ForEach(state.entries) { entry in item(entry, grid: true) }
                }
                .padding(16)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.entries) { entry in item(entry, grid: false) }
                }
                .padding(8)
            }
        }
    }

    private func item(_ entry: FolderStackEntry, grid: Bool) -> some View {
        Button { state.openEntry?(entry.reference) } label: {
            Group {
                if grid {
                    VStack(spacing: 6) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 48, height: 48)
                        Text(verbatim: entry.reference.name).font(.caption).lineLimit(2)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }.frame(minHeight: 78)
                } else {
                    HStack(spacing: 9) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(verbatim: entry.reference.name).lineLimit(1)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 8).frame(height: 34)
                }
            }
            .contentShape(.rect)
            .background(state.selectedID == entry.id ? Color.accentColor.opacity(0.18) : .clear,
                        in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay {
            FolderStackDragSourceView(entry: entry, open: { state.openEntry?(entry.reference) },
                                      completed: { state.dragCompleted?($0) })
        }
        .accessibilityLabel(Text(verbatim: entry.reference.name))
        .accessibilityHint(Text(entry.reference.isFolder ? .folderStackRevealHint : .folderStackOpenHint))
        .accessibilityAddTraits(state.selectedID == entry.id ? .isSelected : [])
        .accessibilityActions {
            Button(entry.reference.isFolder ? .folderStackShowInFinder : .actionOpen) {
                state.openEntry?(entry.reference)
            }
        }
    }
}

private struct FolderStackPanelShape: Shape {
    let chrome: FolderStackChrome

    func path(in rect: CGRect) -> Path {
        let depth = FolderStackGeometry.pointerDepth
        let halfWidth: CGFloat = 10
        var body = rect
        switch chrome.edge {
        case .bottom: body.size.height -= depth
        case .top: body.origin.y += depth; body.size.height -= depth
        case .left: body.origin.x += depth; body.size.width -= depth
        case .right: body.size.width -= depth
        }
        var path = Path(roundedRect: body, cornerRadius: 18)
        var pointer = Path()
        switch chrome.edge {
        case .bottom:
            pointer.move(to: CGPoint(x: chrome.attachment - halfWidth, y: body.maxY - 1))
            pointer.addLine(to: CGPoint(x: chrome.attachment, y: rect.maxY))
            pointer.addLine(to: CGPoint(x: chrome.attachment + halfWidth, y: body.maxY - 1))
        case .top:
            pointer.move(to: CGPoint(x: chrome.attachment - halfWidth, y: body.minY + 1))
            pointer.addLine(to: CGPoint(x: chrome.attachment, y: rect.minY))
            pointer.addLine(to: CGPoint(x: chrome.attachment + halfWidth, y: body.minY + 1))
        case .left:
            pointer.move(to: CGPoint(x: body.minX + 1, y: chrome.attachment - halfWidth))
            pointer.addLine(to: CGPoint(x: rect.minX, y: chrome.attachment))
            pointer.addLine(to: CGPoint(x: body.minX + 1, y: chrome.attachment + halfWidth))
        case .right:
            pointer.move(to: CGPoint(x: body.maxX - 1, y: chrome.attachment - halfWidth))
            pointer.addLine(to: CGPoint(x: rect.maxX, y: chrome.attachment))
            pointer.addLine(to: CGPoint(x: body.maxX - 1, y: chrome.attachment + halfWidth))
        }
        pointer.closeSubpath()
        path.addPath(pointer)
        return path
    }
}

#if DEBUG
@MainActor private enum FolderStackPreviewData {
    static let icon = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)!
    static let entries = [
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/item 2.txt"), name: "item 2.txt", isFolder: false), icon: icon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/item 10.txt"), name: "A document with a deliberately long Finder name.txt", isFolder: false), icon: icon)
    ]
    static func state(_ mode: FolderStackPresentation = .grid, name: String = "Projects",
                      entries suppliedEntries: [FolderStackEntry]? = nil,
                      loading: Bool = false, error: String? = nil) -> FolderStackState {
        FolderStackState(folder: FolderReference(url: URL(fileURLWithPath: "/Preview"), name: name,
                                                  bookmarkData: Data(), presentation: mode),
                         entries: suppliedEntries ?? entries, loading: loading, error: error)
    }
}

#Preview("Grid populated") {
    FolderStackView(state: FolderStackPreviewData.state(), keyboard: false).frame(width: 560, height: 420).padding()
}
#Preview("List, long name, dark") {
    FolderStackView(state: FolderStackPreviewData.state(.list, name: "A very long folder name that must remain on one line"), keyboard: true)
        .frame(width: 560, height: 420).padding().preferredColorScheme(.dark)
}
#Preview("Loading") {
    FolderStackView(state: FolderStackPreviewData.state(entries: [], loading: true), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Empty") {
    FolderStackView(state: FolderStackPreviewData.state(entries: []), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Unavailable") {
    FolderStackView(state: FolderStackPreviewData.state(entries: [], error: "This folder is unavailable."), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Recoverable error") {
    FolderStackView(state: FolderStackPreviewData.state(entries: [], error: "The folder could not be read."), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Reduced motion and transparency") {
    FolderStackView(state: FolderStackPreviewData.state(), keyboard: false, forceOpaqueBackground: true)
        .frame(width: 560, height: 420).padding()
}
#endif

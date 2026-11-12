import SwiftUI

/// The list of folder rows. It scrolls only when the rows are taller than ``maxHeight``;
/// otherwise the rows sit in a plain stack, so nothing clips them.
///
/// Rows slide in from the side as folders arrive and slide out when taken out. While a delete
/// pulls the rows into the orb (`pullTarget` set), each row flies there in turn; a scrolling
/// list stops clipping meanwhile, so rows can leave it.
struct VaporFolderList: View {
    let folders: [VaporFolder]
    let home: URL
    let reduceMotion: Bool
    /// The orb's centre in ``VaporPanelStage/space``, while rows are pulled into it.
    let pullTarget: CGPoint?
    let remove: (VaporFolder.ID) -> Void

    static let maxHeight: CGFloat = 288

    /// The rows' natural height, measured from the stack.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        Group {
            if contentHeight > Self.maxHeight {
                ScrollView {
                    rows
                }
                .scrollIndicators(.never)
                .scrollClipDisabled(pullTarget != nil)
                .frame(height: Self.maxHeight)
            } else {
                rows
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : VaporMotion.rowEnter, value: folders.map(\.id))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                VaporFolderRow(folder: folder, home: home, reduceMotion: reduceMotion) { remove(folder.id) }
                    .modifier(VaporRowPullEffect(index: index, target: pullTarget))
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: 28).combined(with: .scale(scale: 0.94)).combined(with: .opacity),
                        removal: .offset(x: 24).combined(with: .opacity)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }
}

/// Flies a row into the orb: it shrinks to 12 % and fades on its way, starting
/// ``VaporMotion/rowPullStagger`` after the row above it, at most ``VaporMotion/rowPullMaxDelay``.
///
/// The row's frame is read before the transforms, in the panel stage's coordinate space, so the
/// offset is measured from where the row sits in the list (scrolling included).
private struct VaporRowPullEffect: ViewModifier {
    let index: Int
    let target: CGPoint?

    @State private var frame: CGRect = .zero
    @State private var pulled = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(VaporPanelStage.space)) } action: { frame = $0 }
            .scaleEffect(pulled ? 0.12 : 1)
            .offset(pulled ? offset : .zero)
            .opacity(pulled ? 0 : 1)
            .onChange(of: target != nil, initial: true) { _, pulling in
                guard pulling else {
                    pulled = false
                    return
                }
                withAnimation(VaporMotion.rowPull.delay(VaporMotion.rowPullDelay(index: index))) { pulled = true }
            }
    }

    private var offset: CGSize {
        guard let target, frame != .zero else { return .zero }
        return CGSize(width: target.x - frame.midX, height: target.y - frame.midY)
    }
}

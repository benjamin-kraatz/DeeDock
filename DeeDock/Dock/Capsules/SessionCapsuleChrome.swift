import SwiftUI

/// Shared furniture for the Session Capsules panel.
///
/// Every page of the flow — collection, window selection, progress, draft, detail — is built from the
/// same three pieces so a step change never re-flows the window: a header, a scrolling body of labelled
/// cards, and a footer bar carrying that page's primary action. Keeping them here stops each page from
/// inventing its own padding and its own idea of where the action button lives.
enum CapsuleMetrics {
    /// Outer padding of a scrolling page body.
    static let page: CGFloat = 18
    /// Space between labelled sections.
    static let section: CGFloat = 18
    static let cardRadius: CGFloat = 10
    static let footerHorizontal: CGFloat = 16
    static let footerVertical: CGFloat = 12
}

/// Panel-wide motion, disabled as one when the system asks for reduced motion.
struct CapsuleMotion {
    let enabled: Bool

    /// Page-to-page navigation.
    var page: Animation? { enabled ? .smooth(duration: 0.32) : nil }
    /// Hover and press feedback.
    var hover: Animation? { enabled ? .easeOut(duration: 0.14) : nil }
    /// Selection and other direct manipulation.
    var pop: Animation? { enabled ? .snappy(duration: 0.22, extraBounce: 0.12) : nil }
}

private struct CapsuleMotionKey: EnvironmentKey {
    static let defaultValue = CapsuleMotion(enabled: true)
}

extension EnvironmentValues {
    var capsuleMotion: CapsuleMotion {
        get { self[CapsuleMotionKey.self] }
        set { self[CapsuleMotionKey.self] = newValue }
    }
}

// MARK: - Surfaces

extension View {
    /// Read-only counterpart of the draft field surface, for saved capsule detail cards.
    func capsuleReadingCard() -> some View {
        padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: CapsuleMetrics.cardRadius))
    }

    /// The same surface as a draft field, with the accent border carrying selection instead of focus.
    func capsuleSelectionCard(selected: Bool, emphasized: Bool = false) -> some View {
        modifier(CapsuleSelectionCard(selected: selected, emphasized: emphasized))
    }

    /// The page footer: one divider and one row of controls, identical on every page.
    func capsuleFooterBar() -> some View {
        VStack(spacing: 0) {
            Divider()
            self
                .padding(.horizontal, CapsuleMetrics.footerHorizontal)
                .padding(.vertical, CapsuleMetrics.footerVertical)
        }
    }
}

private struct CapsuleSelectionCard: ViewModifier {
    let selected: Bool
    let emphasized: Bool
    @Environment(\.capsuleMotion) private var motion

    func body(content: Content) -> some View {
        content
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.14))
                                 : AnyShapeStyle(.quaternary.opacity(emphasized ? 0.55 : 0.35)),
                        in: .rect(cornerRadius: CapsuleMetrics.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: CapsuleMetrics.cardRadius)
                    .strokeBorder(selected ? AnyShapeStyle(Color.accentColor.opacity(0.75))
                                           : AnyShapeStyle(.quaternary),
                                  lineWidth: selected ? 1.5 : 1)
            }
            .animation(motion.pop, value: selected)
    }
}

/// Row button style: the card lifts under the pointer and settles under a click.
struct CapsuleRowButtonStyle: ButtonStyle {
    @Environment(\.capsuleMotion) private var motion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering && !configuration.isPressed ? 0.04 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(motion.hover, value: hovering)
            .animation(motion.hover, value: configuration.isPressed)
            .onHover { hovering = $0 }
            .environment(\.capsuleRowHovering, hovering)
    }
}

private struct CapsuleRowHoveringKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Lets a row reveal secondary affordances only while the pointer is over it.
    var capsuleRowHovering: Bool {
        get { self[CapsuleRowHoveringKey.self] }
        set { self[CapsuleRowHoveringKey.self] = newValue }
    }
}

// MARK: - Header

/// Where the user is in the two-step creation flow, and where they are going next.
struct CapsuleFlowSteps: View {
    /// 0 while choosing windows, 1 while reviewing the draft.
    let current: Int
    @Environment(\.capsuleMotion) private var motion

    private static let titles: [LocalizedStringResource] = [.capsulesStepChoose, .capsulesStepReview]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.titles.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Capsule().fill(.quaternary).frame(width: 10, height: 1.5)
                }
                step(title, index: index)
            }
        }
        .animation(motion.pop, value: current)
        .accessibilityElement(children: .combine)
    }

    private func step(_ title: LocalizedStringResource, index: Int) -> some View {
        let done = index < current
        let active = index == current
        return HStack(spacing: 4) {
            ZStack {
                Circle().fill(active || done ? AnyShapeStyle(Color.accentColor)
                                             : AnyShapeStyle(.quaternary))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 12, height: 12)
            Text(title)
                .font(.caption2.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}

// MARK: - Empty and permission states

/// The panel's one empty-state layout: the capsule mark, a headline, a line of guidance, one action.
///
/// `ContentUnavailableView` centres a system symbol the panel does not otherwise use; this keeps the
/// drawn mark and the flow's own button styling, so an empty collection looks like the rest of the panel.
struct CapsuleEmptyState<Mark: View>: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var action: LocalizedStringResource?
    var actionSymbol: String?
    var perform: (() -> Void)?
    @ViewBuilder var mark: Mark

    @Environment(\.capsuleMotion) private var motion

    var body: some View {
        VStack(spacing: 14) {
            mark
            VStack(spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action, let perform {
                Button(action: perform) {
                    if let actionSymbol {
                        Label(action, systemImage: actionSymbol)
                    } else {
                        Text(action)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension CapsuleEmptyState where Mark == CapsuleGlyph {
    init(title: LocalizedStringResource, message: LocalizedStringResource,
         action: LocalizedStringResource? = nil, actionSymbol: String? = nil,
         perform: (() -> Void)? = nil) {
        self.init(title: title, message: message, action: action, actionSymbol: actionSymbol,
                  perform: perform) { CapsuleGlyph(size: 52) }
    }
}

/// Recoverable problems, shown in the panel rather than as an alert so the flow stays put.
struct CapsuleErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow).accessibilityHidden(true)
            Text(verbatim: message).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(Text(.capsulesDismiss))
            .accessibilityLabel(Text(.capsulesDismiss))
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: CapsuleMetrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CapsuleMetrics.cardRadius)
                .strokeBorder(.yellow.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

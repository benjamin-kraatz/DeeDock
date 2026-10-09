import SwiftUI

/// The 46 pt status bar: item count and free space, or the running transfer, or a brief
/// completion message; split, preview, and view-mode controls on the right.
struct HubFilesStatusBar: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme
    /// A finished job shown for 2.2 s after it ends.
    @State private var finished: HubFilesTransferStatus?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let transfer = model.currentTransfer {
                    HubFilesTransferProgress(model: model, status: transfer)
                        .id(transfer.jobID)
                } else if let finished {
                    HubFilesTransferDone(status: finished)
                } else {
                    HubFilesIdleStatus(model: model)
                }
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            Spacer(minLength: 8)
            HubFilesLayoutControls(model: model)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: HubFilesMetrics.statusBarHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(height: 0.5)
        }
        .animation(HubFilesMotion.animation(.spring(response: 0.4, dampingFraction: 0.7)), value: model.currentTransfer?.jobID)
        .animation(HubFilesMotion.animation(.spring(response: 0.35, dampingFraction: 0.7)), value: finished?.jobID)
        .task(id: model.finishedTransfer?.jobID) {
            guard let status = model.finishedTransfer, status.phase != .cancelled else { return }
            finished = status
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            finished = nil
        }
    }
}

/// "N items · X available", with the selection count when something is selected.
private struct HubFilesIdleStatus: View {
    let model: HubFilesModel

    var body: some View {
        Text(verbatim: parts.joined(separator: " · "))
            .lineLimit(1)
            .monospacedDigit()
    }

    private var parts: [String] {
        if model.isSearching {
            return [HubFilesFormatting.itemCount(model.searchResults.count)]
        }
        let pane = model.activePane
        var parts = [HubFilesFormatting.itemCount(pane.items.count)]
        if !pane.selection.isEmpty { parts.append(String(localized: .hubFilesSelectedCount(pane.selection.count))) }
        if let available = pane.availableBytes {
            parts.append(String(localized: .hubFilesAvailable(HubFilesFormatting.size(available))))
        }
        return parts
    }
}

/// The completion message: a green check and "Copied N items".
private struct HubFilesTransferDone: View {
    let status: HubFilesTransferStatus

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isFailure ? Color.orange : HubFilesTheme(scheme).fresh)
            Text(verbatim: message)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var isFailure: Bool {
        if case .failed = status.phase { return true }
        return false
    }

    private var message: String {
        if case .failed(let reason) = status.phase {
            return String(localized: status.kind == .copy ? .hubFilesCopyFailed(reason) : .hubFilesMoveFailed(reason))
        }
        return String(localized: status.kind == .copy ? .hubFilesCopied(status.itemCount) : .hubFilesMoved(status.itemCount))
    }
}

/// Split toggle, preview toggle, and the list / icons / columns segmented control, whose raised
/// pill slides to the chosen segment.
private struct HubFilesLayoutControls: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme
    @Namespace private var viewModePill

    var body: some View {
        HStack(spacing: 6) {
            HubFilesStatusIconButton(symbol: "rectangle.split.2x1", label: .hubFilesSplitToggle,
                                     isOn: model.selectedTab.isSplit) { model.toggleSplit() }
            HubFilesStatusIconButton(symbol: "sidebar.right", label: .hubFilesPreviewToggle,
                                     isOn: model.showsPreview) { model.showsPreview.toggle() }
            HStack(spacing: 2) {
                ForEach(HubFilesViewMode.allCases) { mode in
                    HubFilesViewModeSegment(mode: mode, isOn: model.selectedTab.viewMode == mode, pill: viewModePill) {
                        model.setViewMode(mode)
                    }
                }
            }
            .padding(2)
            .background(HubFilesTheme(scheme).chip, in: .rect(cornerRadius: 9))
            .animation(HubFilesMotion.layout, value: model.selectedTab.viewMode)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.hubFilesViewModeLabel))
        }
    }
}

/// A 32 pt icon toggle in the status bar; accent-colored while on.
private struct HubFilesStatusIconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let isOn: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(hovered ? .primary : .secondary))
                .frame(width: 32, height: 32)
                .background(hovered ? HubFilesTheme(scheme).chip : .clear, in: .rect(cornerRadius: 9))
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.9))
        .onHover { hovered = $0 }
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// One segment of the view-mode control.
private struct HubFilesViewModeSegment: View {
    let mode: HubFilesViewMode
    let isOn: Bool
    /// The control's namespace for the sliding "on" pill.
    let pill: Namespace.ID
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(hovered ? .primary : .secondary))
                .frame(width: 30, height: 26)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(scheme == .dark ? HubFilesTheme(scheme).chipHighlight : .white)
                            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 1, y: 0.5)
                            .matchedGeometryEffect(id: "on", in: pill)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.quick, value: hovered)
        .help(Text(mode.title))
        .accessibilityLabel(Text(mode.title))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

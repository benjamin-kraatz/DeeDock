import SwiftUI

/// The compact Launcher's title and app search field.
///
/// The field keeps focus for the whole presentation: arrow keys, Return, and Escape reach the
/// controller's key handler first, so typing never has to leave it.
struct CompactLauncherHeader: View {
    @Bindable var model: CompactLauncherModel
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 16) {
            Text(.launcherTitle)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(text: $model.query, prompt: Text(.launcherCompactSearchPrompt)) {
                    Text(.launcherSearch)
                }
                .textFieldStyle(.plain)
                .focused(focused)
                .autocorrectionDisabled()
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        focused.wrappedValue = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(.launcherClearSearch))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 280)
            .background(.primary.opacity(0.07), in: .capsule)
            .overlay { Capsule().strokeBorder(.primary.opacity(0.08)) }
        }
        .frame(height: CompactLauncherLayout.headerHeight)
    }
}

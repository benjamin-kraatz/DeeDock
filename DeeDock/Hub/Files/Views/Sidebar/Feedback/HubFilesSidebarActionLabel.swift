import SwiftUI

/// What a drop over the sidebar will do, named under the pointer during a drag.
enum HubFilesSidebarAction: Equatable {
    /// Dropping adds the dragged folders to the sidebar.
    case add
    /// Dropping moves the items into the named folder.
    case move(String)
    /// Dropping copies the items into the named folder.
    case copy(String)
    /// Releasing removes the dragged row from the sidebar.
    case remove

    var title: String {
        switch self {
        case .add: String(localized: .hubFilesSidebarAdd)
        case .move(let name): String(localized: .hubFilesSidebarMoveTo(name))
        case .copy(let name): String(localized: .hubFilesSidebarCopyTo(name))
        case .remove: String(localized: .hubFilesSidebarRemove)
        }
    }

    var symbolName: String? {
        switch self {
        case .add: "sidebar.left"
        case .move, .copy: nil
        case .remove: "smoke.fill"
        }
    }
}

/// The small label under the pointer: accent for adding, moving, and copying, dark gray for removing.
///
/// It settles in from 4 pt above over 0.14 s when it first appears. The overlay window keeps the
/// label's view identity while the action changes, so a new title doesn't replay the entrance.
struct HubFilesSidebarActionLabel: View {
    let action: HubFilesSidebarAction

    @Environment(\.colorScheme) private var scheme
    @State private var appeared = HubFilesMotion.reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            if let symbol = action.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(verbatim: action.title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.leading, action.symbolName == nil ? 9 : 7)
        .padding(.trailing, 9)
        .padding(.vertical, 3.5)
        .background(fill, in: .rect(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .fixedSize()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear {
            withAnimation(HubFilesMotion.animation(.easeOut(duration: 0.14))) { appeared = true }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        if action == .remove { return scheme == .dark ? Color(white: 0.23) : Color(white: 0.39) }
        return .accentColor
    }
}

#Preview("Action labels") {
    VStack(alignment: .leading, spacing: 10) {
        HubFilesSidebarActionLabel(action: .add)
        HubFilesSidebarActionLabel(action: .move("Downloads"))
        HubFilesSidebarActionLabel(action: .copy("Transfair"))
        HubFilesSidebarActionLabel(action: .remove)
    }
    .padding(20)
}

import SwiftUI

/// Shared measurements for the System Settings Clone window.
enum SystemSettingsCloneMetrics {
    static let cardRadius: CGFloat = 14
    static let columnWidth: CGFloat = 680
    static let sidebarIdeal: CGFloat = 248
    static let rowInset: CGFloat = 16
    static let rowVerticalInset: CGFloat = 11
    static let rowMinimumHeight: CGFloat = 52
}

/// Warm copper accents that sit beside system materials without replacing them.
enum SystemSettingsClonePalette {
    static let copper = Color(red: 0.72, green: 0.42, blue: 0.28)
    static let terracotta = Color(red: 0.80, green: 0.38, blue: 0.24)
    static let clay = Color(red: 0.48, green: 0.26, blue: 0.18)
    static let sand = Color(red: 0.93, green: 0.82, blue: 0.70)

    /// Category tile gradients. Keep enough contrast for the white symbol.
    static func tileColors(for id: SystemSettingsCloneCategory.ID) -> [Color] {
        switch id {
        case .meAndPrivacy:
            [Color(red: 0.78, green: 0.36, blue: 0.28), Color(red: 0.48, green: 0.20, blue: 0.18)]
        case .network:
            [Color(red: 0.22, green: 0.52, blue: 0.62), Color(red: 0.12, green: 0.30, blue: 0.42)]
        case .displays:
            [Color(red: 0.86, green: 0.52, blue: 0.22), Color(red: 0.58, green: 0.28, blue: 0.12)]
        case .sound:
            [Color(red: 0.72, green: 0.32, blue: 0.42), Color(red: 0.42, green: 0.16, blue: 0.28)]
        case .focus:
            [Color(red: 0.52, green: 0.36, blue: 0.68), Color(red: 0.30, green: 0.18, blue: 0.46)]
        case .accessibility:
            [Color(red: 0.28, green: 0.48, blue: 0.78), Color(red: 0.14, green: 0.26, blue: 0.52)]
        case .general:
            [Color(red: 0.46, green: 0.40, blue: 0.36), Color(red: 0.26, green: 0.22, blue: 0.20)]
        case .powerAndPeople:
            [Color(red: 0.32, green: 0.58, blue: 0.38), Color(red: 0.16, green: 0.34, blue: 0.22)]
        }
    }
}

/// Rounded symbol artwork used by the sidebar and pane rows.
struct SystemSettingsCloneIconTile: View {
    let symbolName: String
    let colors: [Color]
    var size: CGFloat = 28

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    var body: some View {
        shape
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 0.5, y: 0.5)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            }
            .frame(width: size, height: size)
            .shadow(color: colors.last?.opacity(0.35) ?? .clear, radius: size * 0.18, y: 1)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Icon tiles") {
    HStack(spacing: 12) {
        ForEach(SystemSettingsDeepLinkCatalog.categories) { category in
            SystemSettingsCloneIconTile(
                symbolName: category.symbolName,
                colors: SystemSettingsClonePalette.tileColors(for: category.id),
                size: 36
            )
        }
    }
    .padding()
}
#endif

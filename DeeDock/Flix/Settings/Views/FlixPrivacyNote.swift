import SwiftUI

/// How Flix Files handles data, in one calm line beside a lock.
struct FlixPrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(.flixPrivacyNote)
                .font(.system(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

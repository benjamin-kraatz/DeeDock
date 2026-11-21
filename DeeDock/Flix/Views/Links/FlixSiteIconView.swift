import SwiftUI

/// A link row's picture: the site's icon when **Load site icons** is on and it loaded, otherwise a
/// monogram — the host's first letter on a colour picked from the host, so a site keeps its colour.
struct FlixSiteIconView: View {
    let host: String
    var size: CGFloat = FlixStyle.iconSize
    var store: FlixSiteIconStore = .shared

    var body: some View {
        ZStack {
            if let icon = store.icon(for: host) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            } else {
                FlixMonogram(host: host, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: host) { store.request(host) }
    }
}

/// The host's first letter on a rounded square.
struct FlixMonogram: View {
    let host: String
    let size: CGFloat

    private var letter: String {
        let name = host.split(separator: ".").first.map(String.init) ?? host
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    /// One of eight calm hues, the same for a host every time.
    private var tint: Color {
        let hues: [Double] = [0.58, 0.47, 0.36, 0.08, 0.95, 0.75, 0.66, 0.13]
        let sum = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: hues[sum % hues.count], saturation: 0.55, brightness: 0.82)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Text(verbatim: letter)
                    .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
    }
}

#if DEBUG
#Preview("Site monograms") {
    HStack(spacing: 10) {
        ForEach(["portal.example.com", "docs.google.com", "linear.app", "figma.com", "notion.so"], id: \.self) { host in
            FlixSiteIconView(host: host)
        }
    }
    .padding()
}
#endif

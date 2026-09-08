import SwiftUI

/// Cached app artwork; unavailable apps retain their name and a system fallback.
struct BossFightPartyIcon: View {
    let member: BossFightPartyMember
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable() }
            else { Image(systemName: "app.dashed").resizable() }
        }
        .scaledToFit().frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct BossFightPartyView: View {
    let members: [BossFightPartyMember]
    let icons: [String: NSImage]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(members) { member in
                BossFightPartyIcon(member: member, icon: icons[member.id])
                    .accessibilityHidden(false)
                    .accessibilityLabel(Text(verbatim: member.name))
                    .help(member.name)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.bossFightParty))
    }
}

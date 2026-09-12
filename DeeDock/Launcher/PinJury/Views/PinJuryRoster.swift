import SwiftUI

/// Each juror has a name, icon, and stated priority, so color is never the only cue.
struct PinJuryRoster: View {
    let activeJuror: PinJuror?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(PinJuror.allCases) { juror in
                    PinJuryJurorCard(juror: juror, isSpeaking: activeJuror == juror)
                }
            }
            VStack(spacing: 8) {
                ForEach(PinJuror.allCases) { juror in
                    PinJuryJurorCard(juror: juror, isSpeaking: activeJuror == juror)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.pinJuryMeetJurors))
    }
}

private struct PinJuryJurorCard: View {
    let juror: PinJuror
    let isSpeaking: Bool

    var body: some View {
        HStack(spacing: 9) {
            PinJurorAvatar(juror: juror, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(juror.displayName)
                    .font(.callout.weight(.semibold))
                Text(juror.perspective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isSpeaking {
                Image(systemName: "waveform")
                    .foregroundStyle(juror.tint)
                    .accessibilityLabel(Text(.pinJurySpeaking))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PinJuryStyle.card, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSpeaking ? juror.tint.opacity(0.65) : PinJuryStyle.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

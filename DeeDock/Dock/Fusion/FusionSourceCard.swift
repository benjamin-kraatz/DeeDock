import SwiftUI

struct FusionSourceCard: View {
    let source: FusionSource
    let remove: () -> Void
    let replace: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                FusionAppIcon(bundleIdentifier: source.candidate.bundleIdentifier)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: source.candidate.applicationName).font(.headline)
                    Text(verbatim: source.title).lineLimit(3)
                    Text(source.captureState.label).font(.caption).foregroundStyle(.secondary)
                    if let time = source.capturedAt { Text(time, format: .dateTime).font(.caption) }
                }
                Spacer(minLength: 0)
                VStack {
                    Button(.fusionReplace, action: replace)
                    Button(.fusionRemove, action: remove)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}


import SwiftUI

/// The author's thank-you message after the last answer. It closes itself after a while when
/// the author asked for that, otherwise on its button.
struct LauncherSurveyThanksView: View {
    let appearance: AnalyticsSurvey.Appearance
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if let title = appearance.thankYouTitle { Text(verbatim: title).font(.headline) }
                else { Text(.launcherSurveyThanksTitle).font(.headline) }
                Group {
                    if let message = appearance.thankYouMessage { Text(verbatim: message) }
                    else { Text(.launcherSurveyThanksMessage) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer(minLength: 0)
                Button(action: close) {
                    if let label = appearance.thankYouButton { Text(verbatim: label) } else { Text(.launcherSurveyDone) }
                }
                .buttonStyle(.glass)
            }
        }
        .task {
            guard appearance.closesAutomatically else { return }
            try? await Task.sleep(for: .seconds(9))
            if !Task.isCancelled { close() }
        }
    }
}

/// Confirms a dismissal and offers to stop feedback questions altogether. Closes itself.
struct LauncherSurveyDismissedView: View {
    let stopAsking: () -> Void
    let close: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { message; Spacer(minLength: 8); actions }
            VStack(alignment: .leading, spacing: 8) { message; HStack { Spacer(minLength: 0); actions } }
        }
        .task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { close() }
        }
    }

    private var message: some View {
        Text(.launcherSurveyDismissedTitle).font(.callout).foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: stopAsking) { Text(.launcherSurveyStopAsking) }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            Button(action: close) { Text(.launcherSurveyDone) }
                .buttonStyle(.glass)
        }
    }
}

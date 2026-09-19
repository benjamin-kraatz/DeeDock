import SwiftUI

struct AppMeltSetupView: View {
    @Bindable var state: AppMeltSetupState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(.meltTitle, systemImage: "rectangle.split.2x1.fill").font(.largeTitle.bold())
            Text(.meltDescription).foregroundStyle(.secondary)
            if state.createdPair == nil {
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<2) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(index == 0 ? .meltFirstApp : .meltSecondApp).font(.headline)
                        Button { state.choose(index) } label: {
                            if let url = state.urls[index] {
                                Label {
                                    Text(verbatim: FileManager.default.displayName(atPath: url.path)).lineLimit(1)
                                } icon: {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                                }
                            } else { Label(.meltReplacementChoose, systemImage: "macwindow") }
                        }
                        .popover(isPresented: Binding(
                            get: { state.windowPickerSide == index },
                            set: { if !$0 { state.windowPickerSide = nil } }
                        )) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(index == 0 ? .meltFirstApp : .meltSecondApp).font(.headline)
                                AppMeltWindowPickerContents(state: state.windowPicker, disabled: state.busy)
                            }.padding(16).frame(width: 340)
                        }
                        Button(.meltChooseApp) { state.chooseApplication(index) }
                            .font(.caption)
                        if !state.candidates[index].isEmpty {
                            Picker(.meltWindow, selection: $state.selection[index]) {
                                Text(.meltChooseWindow).tag(Optional<ApplicationWindowToken>.none)
                                ForEach(state.candidates[index].filter { $0.token != state.selection[1 - index] }) { window in
                                    Text(verbatim: window.title ?? String(localized: .applicationMenuUntitledWindow))
                                        .tag(Optional(window.token))
                                }
                            }
                        }
                        Text(.meltDropApp).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .overlay { AppMeltSetupDropTarget(state: state, index: index) }
                }
            }
            .disabled(state.busy)
            }
            if let pair = state.createdPair {
                Text(verbatim: pair.title).font(.headline)
                if let message = pair.message { Text(message).foregroundStyle(.orange) }
                HStack {
                    Button(.meltRestore) { state.retryPair() }.disabled(pair.busy)
                    Button(.meltUnpair) { state.discardPair() }.disabled(pair.busy)
                }
                if pair.busy { ProgressView() }
            }
            if let message = state.message { Text(message).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if state.busy { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
            HStack {
                if state.accessEnabled {
                    Label(.meltAccessGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(.meltEnableAccess) { SystemWindowAccessService().requestAccess(); state.refreshAccess() }
                }
                Spacer()
                Button(.meltLaunch) { state.launchAndRefresh() }
                    .disabled(state.createdPair != nil || state.busy || state.urls.contains(where: { $0 == nil }))
                Button(.meltCreate) { state.create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.createdPair != nil || state.busy || state.selection.contains(where: { $0 == nil }) || state.selection[0] == state.selection[1])
            }
            Text(.meltLimitations).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { state.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshAccess() }
        .padding(24)
        .frame(width: 520, height: 480)
    }
}

#Preview("Choose apps") {
    AppMeltSetupView(state: AppMeltSetupState(controller: AppMeltController()))
        .allowsHitTesting(false)
}

#Preview("German · Dark") {
    AppMeltSetupView(state: AppMeltSetupState(controller: AppMeltController()))
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
        .allowsHitTesting(false)
}

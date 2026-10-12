import SwiftUI

/// Lookout's Settings section (the mockup's `renderSettings`): "Search by content", the folders, "Read files on
/// battery too", the model, the index's size and memory, "Read everything again", "Delete index and model", and how
/// Lookout handles data. Before setup it shows the switch and the privacy line only; the switch opens onboarding.
struct LookoutSettingsPane: View {
    let model: LookoutSettingsModel

    var body: some View {
        SettingsPageScaffold {
            SettingsCard {
                SettingsToggleRow(title: .lookoutSettingsSearchByContent,
                                  subtitle: .lookoutSettingsSearchByContentDetail,
                                  isOn: Binding(get: { model.isOn }, set: { model.setOn($0) }))
            }
            if model.isSetUp {
                if let progress = model.progress {
                    LookoutProgressCard(progress: progress, pause: { model.pauseReading() },
                                        resume: { model.resumeReading() })
                }
                LookoutSettingsFoldersCard(model: model)
                SettingsCard {
                    SettingsToggleRow(title: .lookoutBatteryTitle, subtitle: .lookoutBatteryDetail,
                                      isOn: Binding(get: { model.settings.indexOnBattery },
                                                    set: { model.setIndexOnBattery($0) }))
                }
                LookoutSettingsInfoCard(indexBytes: model.indexBytes)
                LookoutSettingsMaintenanceCard(model: model)
            }
            LookoutPrivacyNote()
        }
        .navigationTitle(Text(.lookoutSettingsTitle))
        .task(id: refreshKey) { await model.refresh() }
    }

    /// Counts and size are read again when the index or the folders change.
    private var refreshKey: [String] {
        let counts = model.engine.indexStatus?.counts
        return model.folders + ["\(counts?.searchable ?? -1)", "\(counts?.files ?? -1)", "\(model.isOn)"]
    }
}

/// The model, the index on disk, and the memory while searching.
private struct LookoutSettingsInfoCard: View {
    let indexBytes: Int64?

    var body: some View {
        SettingsCard {
            SettingsRow(title: .lookoutSettingsModel) {
                Text(.lookoutSettingsModelValue).foregroundStyle(.secondary)
            }
            SettingsRow(title: .lookoutSettingsIndexSize) {
                Text(verbatim: indexBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            SettingsRow(title: .lookoutSettingsMemory) {
                Text(.lookoutSettingsMemoryValue)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// "Read everything again" and "Delete index and model" as the mockup draws them: link-style rows, the second in red.
/// Deleting asks first.
private struct LookoutSettingsMaintenanceCard: View {
    let model: LookoutSettingsModel

    @State private var confirmsDelete = false

    var body: some View {
        SettingsCard {
            LookoutSettingsLinkRow(title: .lookoutSettingsRebuild, color: .accentColor) {
                model.readEverythingAgain()
            }
            .disabled(!model.engine.isRunning)
            .help(Text(.lookoutSettingsRebuildHelp))
            Group {
                if model.isDeleting {
                    // Up to `LookoutEngine.closeTimeout` while the service finishes its batch and closes the index.
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(.lookoutSettingsDeleting)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
                } else {
                    LookoutSettingsLinkRow(title: .lookoutSettingsDelete, color: LookoutTheme.failed) {
                        confirmsDelete = true
                    }
                }
            }
        }
        .alert(Text(.lookoutSettingsDeleteConfirmTitle), isPresented: $confirmsDelete) {
            Button(.lookoutSettingsDeleteConfirm, role: .destructive) {
                Task { await model.deleteEverything() }
            }
            Button(.lookoutSettingsDeleteCancel, role: .cancel) {}
        } message: {
            Text(.lookoutSettingsDeleteConfirmMessage)
        }
    }
}

/// A row that is one link-style button.
private struct LookoutSettingsLinkRow: View {
    let title: LocalizedStringResource
    let color: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(minHeight: SettingsMetrics.rowMinimumHeight)
    }
}

#if DEBUG
#Preview("Lookout · ready") {
    LookoutSettingsPane(model: .preview())
        .frame(width: 680, height: 820)
}

#Preview("Lookout · reading, German") {
    LookoutSettingsPane(model: .preview(status: .indexing(remaining: 1_992, progress: 0.61),
                                        progress: .Sample.readingMid))
        .frame(width: 680, height: 900)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Lookout · missing drive, not allowed, dark") {
    LookoutSettingsPane(model: .preview(
        status: .indexing(remaining: 1_204, progress: 0.4),
        folders: LookoutSettingsModel.previewFolders + ["/Volumes/Archive/Scans"],
        missing: ["/Volumes/Archive/Scans"], notPermitted: ["/Users/preview/Downloads"],
        notice: .refused(.homeFolder)))
        .frame(width: 680, height: 900)
        .preferredColorScheme(.dark)
}

#Preview("Lookout · not set up, German") {
    LookoutSettingsPane(model: .preview(status: .notSetUp))
        .frame(width: 680, height: 420)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif

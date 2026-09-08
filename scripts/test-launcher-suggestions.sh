#!/bin/bash
# Run only DEE-26's isolated model, persistence, lifecycle, and navigation tests.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dee26_runner=$(mktemp -d /tmp/dee26-tests.XXXXXX)
trap 'rm -rf "$dee26_runner"' EXIT
mkdir "$dee26_runner/Tests"
mkdir "$dee26_runner/Resources"
xcrun coremlcompiler compile "$repository/DeeDock/Resources/LauncherSuggestions.mlmodel" "$dee26_runner/Resources"
export DEE26_COREML_SEED_URL="$dee26_runner/Resources/LauncherSuggestions.mlmodelc"
sources=(
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionModels.swift
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionEngine.swift
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionTuning.swift
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionSyntheticHistory.swift
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionRecorder.swift
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionBaseline.swift
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionRanking.swift
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionEvidence.swift
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionCoreML.swift
  DeeDock/Launcher/Suggestions/Persistence/LauncherSuggestionsRepository.swift
  DeeDock/Launcher/Suggestions/State/LauncherSuggestionsStore.swift
  DeeDock/Launcher/Suggestions/State/LauncherSuggestionDebugController.swift
  DeeDock/Launcher/Suggestions/State/LauncherSuggestionSyntheticPlayback.swift
  DeeDock/Launcher/State/LauncherBrowseNavigation.swift
  DeeDock/Launcher/Models/LauncherApplication.swift
  DeeDock/Dock/Models/ApplicationReference.swift
  DeeDockTests/LauncherSuggestionTests.swift
  DeeDockTests/LauncherSuggestionNavigationTests.swift
  DeeDockTests/LauncherSuggestionLifecycleTests.swift
  DeeDockTests/LauncherSuggestionEngineTests.swift
  DeeDockTests/LauncherSuggestionEvidenceTests.swift
  DeeDockTests/LauncherSuggestionSyntheticTests.swift
  DeeDockTests/LauncherSuggestionCoreMLTests.swift
)
for source in "${sources[@]}"; do
  cp "$repository/$source" "$dee26_runner/Tests/"
done
cat > "$dee26_runner/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "DEE26FocusedTests", platforms: [.macOS("27.0")], targets: [
    .testTarget(name: "DEE26FocusedTests", path: "Tests", swiftSettings: [
        .swiftLanguageMode(.v5), .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances")
    ])
])
SWIFT
xcrun swift test --package-path "$dee26_runner"

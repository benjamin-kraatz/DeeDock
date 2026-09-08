#!/bin/bash
# Run only DEE-26's isolated model, persistence, lifecycle, and navigation tests.
set -euo pipefail
repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dee26_runner=$(mktemp -d /tmp/dee26-tests.XXXXXX)
trap 'rm -rf "$dee26_runner"' EXIT
mkdir "$dee26_runner/Tests"
sources=(
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionModels.swift
  DeeDock/Launcher/Suggestions/Models/LauncherSuggestionRecorder.swift
  DeeDock/Launcher/Suggestions/Prediction/LauncherSuggestionBaseline.swift
  DeeDock/Launcher/Suggestions/Persistence/LauncherSuggestionsRepository.swift
  DeeDock/Launcher/Suggestions/State/LauncherSuggestionsStore.swift
  DeeDock/Launcher/State/LauncherBrowseNavigation.swift
  DeeDock/Launcher/Models/LauncherApplication.swift
  DeeDock/Dock/Models/ApplicationReference.swift
  DeeDockTests/LauncherSuggestionTests.swift
  DeeDockTests/LauncherSuggestionNavigationTests.swift
  DeeDockTests/LauncherSuggestionLifecycleTests.swift
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

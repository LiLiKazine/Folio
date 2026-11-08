#!/bin/sh
# Runs on Xcode Cloud before every xcodebuild call. $CI_XCODEBUILD_ACTION says which.
#
# Xcode Cloud only exists on the runner, so nothing here changes local builds.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

case "${CI_XCODEBUILD_ACTION:-}" in
build-for-testing)
    # Xcode builds Swift packages with -suppress-warnings, so a warning in FolioCore
    # would pass the scheme's tests. scripts/test.sh runs this same command first;
    # do it here so Xcode Cloud holds FolioCore to the same rule (see CLAUDE.md).
    swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors
    ;;
archive)
    # TestFlight rejects a build number it has seen for the same version, and
    # Version.xcconfig is a fixed 1. Xcode Cloud numbers its builds upward, so use that.
    sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}/" \
        app/Config/Version.xcconfig
    echo "Build number set to ${CI_BUILD_NUMBER}"
    ;;
esac

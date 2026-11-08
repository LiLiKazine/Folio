#!/usr/bin/env bash
# Build, install, and launch. Defaults to the first enabled platform.
#   ./scripts/run.sh            # first enabled platform
#   ./scripts/run.sh macos
# With --screenshot, save proof of launch to build/launch-<platform>.png.
# The platform and --screenshot may appear in either order.
# Each platform gets its own derived-data directory (build/dd-<platform>): a
# shared one made `find ... -print -quit` pick up a stale build product left
# by whichever platform built there first, launching the wrong app.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/_common.sh

PLATFORM=""
SHOT=0
for arg in "$@"; do
    case "$arg" in
        --screenshot) SHOT=1 ;;
        ios|macos)    PLATFORM="$arg" ;;
        *)            echo "unknown argument: $arg" >&2; exit 1 ;;
    esac
done
[[ -n "$PLATFORM" ]] || PLATFORM="$(first_platform)"

# Validates against scripts/.platforms, same clean error as build.sh/test.sh,
# rather than falling into xcodebuild and dying on a raw destination-matching
# failure.
platforms "$PLATFORM" >/dev/null || exit 1

mkdir -p build

case "$PLATFORM" in
    ios)
        resolve_simulator || exit 1
        say "booting $SIMULATOR"
        xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
        xcrun simctl bootstatus "$SIMULATOR" -b >/dev/null

        say "building for simulator"
        xcb run-build-ios \
            -project "$PROJECT" -scheme "$SCHEME" \
            -destination "$(destination ios)" \
            -derivedDataPath build/dd-ios build

        APP="$(find build/dd-ios/Build/Products -maxdepth 2 -name "${APP_NAME}.app" -print -quit)"
        [[ -n "$APP" ]] || { echo "could not locate built .app" >&2; exit 1; }

        say "installing and launching"
        xcrun simctl install "$SIMULATOR" "$APP"
        xcrun simctl launch "$SIMULATOR" "$BUNDLE_ID"

        if [[ "$SHOT" == 1 ]]; then
            sleep 3
            # Devices with several displays (foldables) make `screenshot`
            # refuse with EINVAL until a display is named; retry on the
            # primary display when that happens.
            if ! out="$(xcrun simctl io "$SIMULATOR" screenshot build/launch-ios.png 2>&1)"; then
                display="$(printf '%s\n' "$out" | grep -oE -- '--display=[0-9]+.*\(primary\)' | grep -oE '[0-9]+' | head -1)"
                [[ -n "$display" ]] || { printf '%s\n' "$out" >&2; exit 1; }
                xcrun simctl io "$SIMULATOR" screenshot --display="$display" build/launch-ios.png
            fi
            say "screenshot: build/launch-ios.png"
        fi
        ;;
    macos)
        say "building for macOS"
        xcb run-build-macos \
            -project "$PROJECT" -scheme "$SCHEME" \
            -destination "$(destination macos)" \
            -derivedDataPath build/dd-macos build

        APP="$(find build/dd-macos/Build/Products -maxdepth 2 -name "${APP_NAME}.app" -print -quit)"
        [[ -n "$APP" ]] || { echo "could not locate built .app" >&2; exit 1; }

        say "launching"
        open "$APP"

        # `open` returns 0 once LaunchServices accepts the bundle — an app
        # that crashes on launch still "opens" successfully. Poll for the
        # process actually running before calling this a pass.
        LAUNCHED=0
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if pgrep -f "/${APP_NAME}.app/" >/dev/null 2>&1; then
                LAUNCHED=1
                break
            fi
            sleep 0.5
        done
        [[ "$LAUNCHED" == 1 ]] \
            || { echo "launch failed: ${APP_NAME}.app is not running after open" >&2; exit 1; }

        if [[ "$SHOT" == 1 ]]; then
            sleep 3
            screencapture -x build/launch-macos.png
            say "screenshot: build/launch-macos.png"
        fi
        ;;
    *)
        echo "unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

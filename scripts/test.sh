#!/usr/bin/env bash
# Run the test suite on every enabled platform, or one named platform.
# Full xcodebuild output lands in build/last-test.log — separate from
# build/last-build.log, so a red test never destroys the build output before it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/_common.sh

# The SPM core, when present, is the fast headless loop — run it first so a
# domain-logic failure surfaces before any simulator boots.
if [[ -d "app/${APP_NAME}Core" ]]; then
    say "testing ${APP_NAME}Core (headless)"
    # -warnings-as-errors is passed here rather than declared in Package.swift:
    # in the manifest it conflicts with the -suppress-warnings that Xcode applies
    # to package dependencies, which breaks the app build. See Package.swift.
    # This is therefore the ONLY place warnings-as-errors reaches the core package.
    swift test --package-path "app/${APP_NAME}Core" -Xswiftc -warnings-as-errors
fi

plats="$(platforms "${1:-}")" || exit 1
for platform in $plats; do
    say "testing $platform"
    dest="$(destination "$platform")" || exit 1
    xcb last-test \
        -project "$PROJECT" -scheme "$SCHEME" \
        -destination "$dest" \
        test
done

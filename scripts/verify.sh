#!/usr/bin/env bash
# The green gate. Every enabled platform must format, build, test, and launch.
# A platform listed in SUPPORTED_PLATFORMS but never verified is worse than one
# never claimed, so this walks the full list.
#
# SKIP_LAUNCH=1 skips only step 4 (launch), running format/build/test as usual.
# Set it on headless CI runners, where `open` and `screencapture` (macOS) are
# unreliable with no attached display. Unset or any other value runs the full
# gate, launch and screenshot included. The skip is always printed loudly —
# a silently skipped gate step is worse than a failing one.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/_common.sh

# A component that exists but is wired into nothing makes the gate report green
# over a path it never compiled. That is how the core package shipped for a while
# with a latent build failure: `swift test` exercised it, xcodebuild never did,
# and the two never overlapped. If the package is here, it must be in the target.
if [[ -d "app/${APP_NAME}Core" ]]; then
    if ! grep -q 'XCSwiftPackageProductDependency' "$PROJECT/project.pbxproj"; then
        echo "app/${APP_NAME}Core exists but is not linked into any target." >&2
        echo "The gate would then pass without ever compiling it through Xcode." >&2
        echo "Link it (Xcode ▸ target ▸ Frameworks) or delete the package." >&2
        exit 1
    fi
fi

say "1/4 format"
./scripts/format.sh --check

for platform in $(platforms ""); do
    say "2/4 build ($platform)"
    ./scripts/build.sh "$platform"

    say "3/4 test ($platform)"
    ./scripts/test.sh "$platform"

    if [[ "${SKIP_LAUNCH:-}" == "1" ]]; then
        say "4/4 launch ($platform) — SKIPPED (SKIP_LAUNCH=1)"
    else
        say "4/4 launch ($platform)"
        ./scripts/run.sh "$platform" --screenshot
    fi
done

say "green — all enabled platforms format, build, test, and launch"

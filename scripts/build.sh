#!/usr/bin/env bash
# Build every enabled platform, or one named platform.
#   ./scripts/build.sh          # all enabled
#   ./scripts/build.sh macos    # just macOS
# Defaults to the Debug configuration; CONFIGURATION=Release overrides it.
# Full xcodebuild output lands in build/last-build.log either way.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/_common.sh

plats="$(platforms "${1:-}")" || exit 1
for platform in $plats; do
    say "building $platform ($CONFIGURATION)"
    dest="$(destination "$platform")" || exit 1
    xcb last-build \
        -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "$dest" \
        build
done

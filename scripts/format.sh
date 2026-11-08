#!/usr/bin/env bash
# Format in place, or with --check verify formatting without writing.
# swift-format ships in the Xcode toolchain; nothing to install.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/_common.sh

if [[ "${1:-}" == "--check" ]]; then
    say "checking formatting"
    xcrun swift-format lint --recursive --strict app
else
    say "formatting"
    xcrun swift-format format --in-place --recursive app
fi

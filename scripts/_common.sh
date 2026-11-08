# Shared settings and helpers for the project scripts.
# shellcheck shell=bash

APP_NAME="Folio"
BUNDLE_ID="io.lilikaine.github.folio"
PROJECT="app/${APP_NAME}.xcodeproj"
SCHEME="$APP_NAME"
SIMULATOR="${SIMULATOR:-}"

# The scheme's Run action is Debug, so that is what build.sh compiles. Override
# to compile Release.xcconfig's `wholemodule` + VALIDATE_PRODUCT path, which
# nothing in the normal loop exercises:
#   CONFIGURATION=Release ./scripts/build.sh macos
# Only build.sh honours it. test.sh stays on Debug because Release does not set
# ENABLE_TESTABILITY, and run.sh stays on Debug because its job is to prove the
# everyday debug loop launches.
CONFIGURATION="${CONFIGURATION:-Debug}"

say() { printf '\n==> %s\n' "$1"; }

# Run xcodebuild with its full output captured to build/<name>.log.
#
# Piping xcodebuild through `tail -5` propagated the exit code correctly but
# discarded the compiler diagnostic, which is the one thing an agent debugging a
# red gate needs — and it hid the `** BUILD SUCCEEDED **` line on green runs too,
# so CI logs showed neither a verdict nor a reason. The full log always lands on
# disk under build/ (gitignored); the console gets the verdict on success and the
# tail plus a pointer to the log on failure.
xcb() {  # xcb <log-name> <xcodebuild args...>
    local name="$1"; shift
    local log="build/$name.log"
    mkdir -p build
    if ! xcodebuild "$@" >"$log" 2>&1; then
        echo "--- last 50 lines of $log ---" >&2
        tail -50 "$log" >&2
        echo "--- full xcodebuild output: $log ---" >&2
        return 1
    fi
    # xcodebuild's verdict lines look like `** BUILD SUCCEEDED **`. No match is
    # not a failure (some actions print none), hence the `|| true`.
    grep -E '^\*\* .+ \*\*' "$log" | tail -1 || true
    echo "log: $log"
}

# Resolves $SIMULATOR to an available iPhone simulator, once. Resolves to the
# device UDID rather than the name: simulator names are not unique on a
# machine with several runtimes installed (two "iPhone Duo" entries, say), and
# an ambiguous name makes xcodebuild refuse the destination. A UDID is unique
# by construction and is accepted everywhere a name is (xcodebuild -destination
# id=, simctl boot/install/launch/io). The SIMULATOR env var still wins if set,
# as either a UDID or a unique name, so `SIMULATOR="iPhone 15" ./scripts/build.sh
# ios` keeps working as an escape hatch.
#
# Picks the newest runtime's last-listed iPhone. `|| true` on the pipeline keeps
# a no-match `grep` from tripping `errexit` before the emptiness check below
# ever runs. Callers must propagate a non-zero return themselves
# (`resolve_simulator || exit 1`) — this function returns rather than exits, so
# it behaves the same whether it's called directly or from inside a `$(...)`
# command substitution (e.g. `destination`), where a bare `exit` would only kill
# the subshell and let the caller carry on with an empty destination.
resolve_simulator() {
    [[ -n "$SIMULATOR" ]] && return 0
    SIMULATOR="$(xcrun simctl list devices available 2>/dev/null \
        | grep -E '^ +iPhone .*\([0-9A-F-]{36}\)' \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' \
        | tail -1 || true)"
    if [[ -z "$SIMULATOR" ]]; then
        echo "no available iPhone simulator found (xcrun simctl list devices available)." >&2
        echo "Install one via Xcode > Settings > Platforms, or override with SIMULATOR=\"<udid or unique device name>\"." >&2
        return 1
    fi
}

# xcodebuild wants `id=` for a UDID and `name=` for anything else.
simulator_destination_key() {
    if [[ "$SIMULATOR" =~ ^[0-9A-F-]{36}$ ]]; then echo id; else echo name; fi
}

# Echo the enabled platforms, or just the one requested.
platforms() {
    local want="${1:-}"
    local all
    all="$(tr ',' ' ' < scripts/.platforms)"
    if [[ -n "$want" ]]; then
        for p in $all; do [[ "$p" == "$want" ]] && { echo "$want"; return; }; done
        echo "platform '$want' is not enabled for this project" >&2
        return 1
    fi
    echo "$all"
}

first_platform() { platforms "" | awk '{print $1}'; }

destination() {
    case "$1" in
        ios)   resolve_simulator || return 1; echo "platform=iOS Simulator,$(simulator_destination_key)=$SIMULATOR" ;;
        macos) echo "platform=macOS" ;;
        *)     echo "unknown platform: $1" >&2; return 1 ;;
    esac
}

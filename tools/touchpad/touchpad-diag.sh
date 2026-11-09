#!/usr/bin/env bash
# Record what libinput sees from the touchpad while you reproduce a
# click-drag and a tap-drag problem. Read-only: it only listens.
#
# Usage: sudo ./touchpad-diag.sh [--seconds N] [--out FILE]
#   --seconds N   length of each of the two phases (default 20)
#   --out FILE    also write the report to FILE (owned by the sudo user)
set -u

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
. "$DIR/common.sh"

SECS=20
OUT=""
while [ $# -gt 0 ]; do
    case $1 in
        --seconds)
            SECS=${2:?--seconds needs a number}
            shift
            ;;
        --out)
            OUT=${2:?--out needs a file}
            shift
            ;;
        *)
            sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
            exit 2
            ;;
    esac
    shift
done
[[ $SECS =~ ^[0-9]+$ ]] || tp_fail "--seconds must be a whole number"

tp_need_root
command -v libinput >/dev/null 2>&1 || tp_fail "libinput not found (apt install libinput-tools)"
dev=$(tp_touchpad_event) || tp_fail "no input node with Touchpad in its name"

RAW=$(mktemp)
cleanup() {
    rm -f "$RAW"
    if [ -n "$OUT" ]; then
        tp_chown_for_sudo "$OUT"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if [ -n "$OUT" ]; then
    : >"$OUT"
fi
emit() {
    printf '%s\n' "$*"
    if [ -n "$OUT" ]; then
        printf '%s\n' "$*" >>"$OUT"
    fi
}

record() {
    local title=$1 prompt=$2 rc filtered
    echo "$prompt Starting in 3 s."
    sleep 3
    emit "## $title"
    : >"$RAW"
    timeout -s INT "$SECS" stdbuf -oL libinput debug-events --device "$dev" --enable-tap --enable-drag >"$RAW" 2>&1
    rc=$?
    if [ "$rc" != 0 ] && [ "$rc" != 124 ] && [ "$rc" != 130 ]; then
        emit "WARN: libinput exited with status $rc"
    fi
    filtered=$(grep -v -E 'POINTER_MOTION|SCROLL_FINGER' "$RAW")
    if [ -n "$filtered" ]; then
        emit "$filtered"
    else
        emit "(no events)"
    fi
}

emit "## device"
emit "$(libinput list-devices | awk '/^Device:.*[Tt]ouchpad/{f=1} f{print} f&&/^$/{exit}')"
emit "## events ($dev, $SECS s per phase)"
record "PHASE 1 click-drag" "PHASE 1 ($SECS s): physical CLICK-DRAG. Press the pad down until it clicks, hold, and drag."
record "PHASE 2 tap-drag" "PHASE 2 ($SECS s): TAP-DRAG. Tap once, then immediately touch down again and drag."
echo "done"

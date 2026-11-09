#!/usr/bin/env bash
# Temporarily bind the touchpad to hid-generic, count its button events, then
# put back the original driver. While swapped the pad may act like a plain
# mouse (no gestures). The original driver and the hid module parameter are
# restored on exit, also on Ctrl-C.
#
# Usage: sudo ./driver-swap-test.sh [--seconds N] [--yes] [--out FILE]
#   --seconds N   how long to listen for presses (default 15)
#   --yes         do not ask before swapping
#   --out FILE    also write the output to FILE (owned by the sudo user)
set -u

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
. "$DIR/common.sh"

SECS=15
ASSUME_YES=0
OUT=""
while [ $# -gt 0 ]; do
    case $1 in
        --seconds)
            SECS=${2:?--seconds needs a number}
            shift
            ;;
        --yes)
            ASSUME_YES=1
            ;;
        --out)
            OUT=${2:?--out needs a file}
            shift
            ;;
        *)
            sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
            exit 2
            ;;
    esac
    shift
done
[[ $SECS =~ ^[0-9]+$ ]] || tp_fail "--seconds must be a whole number"

tp_need_root
if [ -n "$OUT" ]; then
    exec > >(tee "$OUT") 2>&1
fi

DRIVERS=/sys/bus/hid/drivers
PARAM=/sys/module/hid/parameters/ignore_special_drivers

HID=$(tp_hid_id) || tp_fail "touchpad not found"
ORIG=$(tp_driver "$HID")
[ -n "$ORIG" ] || tp_fail "touchpad $HID is not bound to any driver; nothing to swap"
[ "$ORIG" != hid-generic ] || tp_fail "touchpad $HID is already on hid-generic; nothing to swap"
[ -w "$PARAM" ] || tp_fail "$PARAM is not writable"
ORIG_PARAM=$(cat "$PARAM")

SWAPPED=0
restore() {
    local now
    if [ "$SWAPPED" = 1 ]; then
        echo "$ORIG_PARAM" >"$PARAM"
        if [ "$(tp_driver "$HID")" = hid-generic ]; then
            echo "$HID" >"$DRIVERS/hid-generic/unbind"
        fi
        if [ "$(tp_driver "$HID")" != "$ORIG" ]; then
            echo "$HID" >"$DRIVERS/$ORIG/bind"
        fi
        now=$(tp_driver "$HID")
        if [ "$now" = "$ORIG" ]; then
            echo "restored: $now"
        else
            echo "RESTORE FAILED: $HID is on '${now:-no driver}', expected $ORIG." >&2
            echo "Try: echo $HID | sudo tee $DRIVERS/$ORIG/bind   (or reboot)" >&2
        fi
    fi
    if [ -n "$OUT" ]; then
        tp_chown_for_sudo "$OUT"
    fi
}
trap restore EXIT
trap 'exit 130' INT TERM

echo "touchpad $HID is on $ORIG; it will be moved to hid-generic for $SECS s and then restored"
if [ "$ASSUME_YES" != 1 ]; then
    read -r -p "Continue? [y/N] " answer </dev/tty
    [ "$answer" = y ] || [ "$answer" = Y ] || exit 1
fi

SWAPPED=1
echo 1 >"$PARAM"
echo "$HID" >"$DRIVERS/$ORIG/unbind"
echo "$HID" >"$DRIVERS/hid-generic/bind"
sleep 1
echo "now on: $(tp_driver "$HID")"

nodes=()
while IFS= read -r n; do
    nodes+=("$n")
done < <(tp_event_nodes "$HID")
[ "${#nodes[@]}" -gt 0 ] || tp_fail "no input nodes appeared after the swap"
echo "input nodes: ${nodes[*]}"
echo "PRESS the pad down firmly 5 times now ($SECS s). BTN_LEFT with value=1 is a click down."
python3 -I "$DIR/allkeys.py" --hid "$HID" --seconds "$SECS"

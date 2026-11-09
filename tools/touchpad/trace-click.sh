#!/usr/bin/env bash
# Trace kernel input events with kprobes while you press the pad, to see
# whether a click reaches the input layer (x86_64 only).
#
# Usage: sudo ./trace-click.sh [--seconds N] [--keep-raw FILE]
#   --seconds N       capture length (default 20)
#   --keep-raw FILE   also save the raw trace to FILE (owned by the sudo user)
#
# PRIVACY: the probe sees events from EVERY input device, keystrokes
# included. Do not type while it runs. Only per-code counts are printed; the
# raw trace is discarded unless you pass --keep-raw.
#
# Everything it creates (two kprobes, the trace buffer size) is removed or
# restored on exit, also on Ctrl-C.
set -u

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
. "$DIR/common.sh"

T=/sys/kernel/tracing
SECS=20
KEEP=""
while [ $# -gt 0 ]; do
    case $1 in
        --seconds)
            SECS=${2:?--seconds needs a number}
            shift
            ;;
        --keep-raw)
            KEEP=${2:?--keep-raw needs a file}
            shift
            ;;
        *)
            sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
            exit 2
            ;;
    esac
    shift
done
[[ $SECS =~ ^[0-9]+$ ]] || tp_fail "--seconds must be a whole number"

tp_need_root
[ "$(uname -m)" = x86_64 ] || tp_fail "the probe uses x86_64 argument registers"
[ -d "$T" ] || tp_fail "$T not found (is tracefs mounted?)"

ORIG_BUF=$(cat "$T/buffer_size_kb")
ORIG_BUF=${ORIG_BUF%% *}

cleanup() {
    local p
    for p in tpdiag_ie tpdiag_sf; do
        if [ -e "$T/events/kprobes/$p/enable" ]; then
            echo 0 >"$T/events/kprobes/$p/enable"
        fi
        if grep -q "$p" "$T/kprobe_events"; then
            echo "-:$p" >>"$T/kprobe_events"
        fi
    done
    echo "$ORIG_BUF" >"$T/buffer_size_kb"
    : >"$T/trace"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

: >"$T/trace"
echo 8192 >"$T/buffer_size_kb"
echo 'p:tpdiag_ie input_event type=%si:u32 code=%dx:u32 value=%cx:s32' >>"$T/kprobe_events" || tp_fail "could not add the input_event probe"
if ! echo 'p:tpdiag_sf hid_multitouch:mt_sync_frame' >>"$T/kprobe_events"; then
    echo "WARN: mt_sync_frame probe failed (hid_multitouch not loaded?); continuing without it"
fi
echo 1 >"$T/events/kprobes/tpdiag_ie/enable"
if [ -d "$T/events/kprobes/tpdiag_sf" ]; then
    echo 1 >"$T/events/kprobes/tpdiag_sf/enable"
fi

MSG="PRESS the pad down firmly about once a second for $SECS seconds NOW. Do not type."
echo "$MSG"
if [ -n "${SUDO_USER:-}" ] && command -v notify-send >/dev/null 2>&1; then
    runuser -u "$SUDO_USER" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" notify-send -u critical "Touchpad test" "$MSG" 2>/dev/null
fi
sleep "$SECS"

echo 0 >"$T/events/kprobes/tpdiag_ie/enable"
if [ -d "$T/events/kprobes/tpdiag_sf" ]; then
    echo 0 >"$T/events/kprobes/tpdiag_sf/enable"
fi

if [ -n "$KEEP" ]; then
    cp "$T/trace" "$KEEP"
    tp_chown_for_sudo "$KEEP"
fi
echo "mt_sync_frame calls: $(grep -c tpdiag_sf "$T/trace")"
echo "key events (type=0x1) by code,value:"
grep tpdiag_ie "$T/trace" | grep -E 'type=0x1 ' | sed -E 's/.*code=(0x[0-9a-f]+) value=(-?[0-9]+).*/code=\1 value=\2/' | sort | uniq -c | sort -rn | sed -n '1,30p'
echo "(code=0x110 is BTN_LEFT; value=1 is down, 0 is up)"

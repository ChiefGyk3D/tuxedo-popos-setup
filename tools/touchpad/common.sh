#!/usr/bin/env bash
# Shared discovery helpers for the touchpad diagnostics. Sourced, never run.
# shellcheck shell=bash
#
# The touchpad is found at run time, never by a hard-coded device id: it is
# the first input node whose name contains "Touchpad". Set TP_HID (for
# example 0018:VVVV:PPPP.0001) to override the HID id.
# The same discovery lives in allkeys.py and click-hid.py; keep them in sync.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "common.sh is sourced by the other scripts, not run directly" >&2
    exit 2
fi

HID_ID_PATTERN='[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}'

tp_fail() {
    echo "ERROR: $*" >&2
    exit 1
}

tp_need_root() {
    [ "$(id -u)" = 0 ] || tp_fail "run with sudo"
}

# tp_touchpad_event: print the /dev/input/eventN node named like a touchpad.
tp_touchpad_event() {
    local f node
    for f in /sys/class/input/event*/device/name; do
        [ -e "$f" ] || continue
        if grep -qi touchpad "$f"; then
            node=$(basename "$(dirname "$(dirname "$f")")")
            printf '/dev/input/%s\n' "$node"
            return 0
        fi
    done
    return 1
}

# tp_hid_id: print the HID device id of the touchpad (TP_HID wins if set).
tp_hid_id() {
    local ev real
    if [ -n "${TP_HID:-}" ]; then
        printf '%s\n' "$TP_HID"
        return 0
    fi
    ev=$(tp_touchpad_event) || return 1
    real=$(readlink -f "/sys/class/input/$(basename "$ev")")
    grep -oE -m 1 "$HID_ID_PATTERN" <<<"$real"
}

# tp_driver hid: name of the driver the HID device is bound to, or nothing.
tp_driver() {
    local link=/sys/bus/hid/devices/$1/driver
    if [ -e "$link" ]; then
        basename "$(readlink -f "$link")"
    fi
}

# tp_event_nodes hid: every /dev/input/eventN that belongs to the HID device.
tp_event_nodes() {
    local e
    for e in /sys/class/input/event*; do
        [ -e "$e" ] || continue
        if [[ "$(readlink -f "$e")" == *"/$1/"* ]]; then
            printf '/dev/input/%s\n' "$(basename "$e")"
        fi
    done
}

# tp_chown_for_sudo file: hand a file written as root back to the sudo user.
tp_chown_for_sudo() {
    if [ -n "${SUDO_UID:-}" ] && [ -e "$1" ]; then
        chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$1"
    fi
}

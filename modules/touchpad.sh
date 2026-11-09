#!/usr/bin/env bash
# Module: touchpad diagnostics. Sourced by install.sh, never run.
# shellcheck shell=bash
#
# Diagnostics only. There is no boot-time fix in this version; that fix waits
# on a reboot test (see tools/touchpad/README.md). This module installs what
# the diagnostics need (libinput-tools provides `libinput debug-events`) and
# checks that the tools are in the checkout. It never touches a driver.

TOUCHPAD_TOOLS=(touchpad-diag.sh click-hid.py allkeys.py trace-click.sh driver-swap-test.sh)

mod_touchpad_check() {
    local t
    check_pkgs libinput-tools
    for t in "${TOUCHPAD_TOOLS[@]}"; do
        if [ -f "$ROOT/tools/touchpad/$t" ]; then
            report ok "tools/touchpad/$t"
        else
            report missing "tools/touchpad/$t"
        fi
    done
}

mod_touchpad_apply() {
    local t
    if step "install libinput-tools (diagnostics dependency)"; then
        apt_install_missing libinput-tools
    fi
    if step "list the touchpad diagnostics"; then
        for t in "${TOUCHPAD_TOOLS[@]}"; do
            [ -f "$ROOT/tools/touchpad/$t" ] || die "missing tools/touchpad/$t"
        done
        echo "diagnostics are in $ROOT/tools/touchpad/ (read its README.md first); nothing was changed on the system"
    fi
}

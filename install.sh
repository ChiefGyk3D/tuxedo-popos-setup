#!/usr/bin/env bash
# tuxedo-popos-setup: configurable, idempotent workstation installer for a
# TUXEDO laptop running Pop!_OS 24.04.
#
#   sudo ./install.sh              apply every enabled module
#   ./install.sh --check           read-only: report what is missing (no root)
#   ./install.sh --dry-run         print what apply would do, change nothing
#   ./install.sh --config FILE     use FILE instead of config/setup.conf
#
# Modules run in this order and the run stops at the first error:
# tuxedo, devtools, flatpaks, touchpad. Logs go to
# ~/.local/state/tuxedo-popos-setup/ of the user who ran sudo.
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=modules/tuxedo.sh
. "$ROOT/modules/tuxedo.sh"
# shellcheck source=modules/devtools.sh
. "$ROOT/modules/devtools.sh"
# shellcheck source=modules/flatpaks.sh
. "$ROOT/modules/flatpaks.sh"
# shellcheck source=modules/touchpad.sh
. "$ROOT/modules/touchpad.sh"

MODE=apply
DRY_RUN=0
CONFIG=""
MISSING=0
APT_DIRTY=0
WORKDIR=""
CURRENT_MODULE=""

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case $1 in
        --check)
            MODE=check
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --config)
            [ $# -ge 2 ] || die "--config needs a file"
            CONFIG=$2
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

resolve_target_user

# Defaults; config/setup.conf overrides them.
set_defaults() {
    : "${ENABLE_TUXEDO:=1}" "${ENABLE_DEVTOOLS:=1}" "${ENABLE_FLATPAKS:=1}" "${ENABLE_TOUCHPAD_FIX:=0}"
    : "${DEVTOOLS_UV:=1}" "${DEVTOOLS_RUSTUP:=1}" "${DEVTOOLS_GO:=1}" "${DEVTOOLS_TOFU:=1}"
    : "${DEVTOOLS_GH:=1}" "${DEVTOOLS_VSCODE:=1}" "${DEVTOOLS_PODMAN:=1}"
    if ! declare -p APT_PACKAGES >/dev/null 2>&1; then
        APT_PACKAGES=(build-essential cmake pkg-config git python3-venv pipx)
    fi
    if ! declare -p FLATPAK_APPS >/dev/null 2>&1; then
        FLATPAK_APPS=(com.discordapp.Discord one.ablaze.floorp)
    fi
}

# The config is sourced as shell, so it must not be writable by anyone else.
load_config() {
    local file=$CONFIG
    if [ -z "$file" ] && [ -f "$ROOT/config/setup.conf" ]; then
        file=$ROOT/config/setup.conf
    fi
    if [ -n "$file" ]; then
        [ -f "$file" ] || die "config file not found: $file"
        if [ -n "$(find "$file" -maxdepth 0 -perm /022)" ]; then
            die "config file $file is group or world writable; run: chmod go-w"
        fi
        local owner
        owner=$(stat -c %U "$file")
        if [ "$owner" != root ] && [ "$owner" != "$TARGET_USER" ]; then
            die "config file $file must be owned by root or $TARGET_USER"
        fi
        # shellcheck source=config/setup.conf.example
        . "$file"
        info "config: $file"
    else
        info "config: none found, using defaults (copy config/setup.conf.example to config/setup.conf)"
    fi
    set_defaults
}

setup_logging() {
    local dir=${XDG_STATE_HOME:-$TARGET_HOME/.local/state}/tuxedo-popos-setup
    as_user mkdir -p "$dir"
    LOG_FILE=$dir/$(date +%Y%m%d-%H%M%S)-$MODE.log
    as_user touch "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

check_os() {
    local id version
    id=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
    version=$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")
    if [ "$id" = pop ] && [ "$version" = 24.04 ]; then
        return 0
    fi
    if [ "$MODE" = apply ] && [ "$DRY_RUN" = 0 ]; then
        die "this installer supports Pop!_OS 24.04 only (found $id $version)"
    fi
    warn "not Pop!_OS 24.04 (found $id $version); results below may not apply"
}

module_enabled() {
    case $1 in
        tuxedo) [ "$ENABLE_TUXEDO" = 1 ] ;;
        devtools) [ "$ENABLE_DEVTOOLS" = 1 ] ;;
        flatpaks) [ "$ENABLE_FLATPAKS" = 1 ] ;;
        touchpad) [ "$ENABLE_TOUCHPAD_FIX" = 1 ] ;;
        *) return 1 ;;
    esac
}

cleanup() {
    if [ -n "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}

on_error() {
    echo "ERROR: module '${CURRENT_MODULE:-startup}' failed near line $1; stopping" >&2
}

main() {
    local m
    load_config
    setup_logging
    trap cleanup EXIT
    trap 'on_error $LINENO' ERR
    info "tuxedo-popos-setup: mode=$MODE dry-run=$DRY_RUN user=$TARGET_USER log=$LOG_FILE"
    check_os
    if [ "$MODE" = apply ] && [ "$DRY_RUN" = 0 ]; then
        require_root
        WORKDIR=$(mktemp -d /var/tmp/tuxedo-popos-setup.XXXXXX)
    else
        WORKDIR=$(mktemp -d)
    fi
    # gpg keeps its state in the scratch dir, not in the user's or root's home.
    mkdir -m 700 "$WORKDIR/gnupg"
    export GNUPGHOME=$WORKDIR/gnupg
    for m in tuxedo devtools flatpaks touchpad; do
        CURRENT_MODULE=$m
        if ! module_enabled "$m"; then
            echo "[skip] module $m is disabled"
            continue
        fi
        echo
        echo "## module: $m"
        if [ "$MODE" = check ]; then
            "mod_${m}_check"
        else
            "mod_${m}_apply"
        fi
    done
    CURRENT_MODULE=""
    echo
    if [ "$MODE" = check ]; then
        if [ "$MISSING" -gt 0 ]; then
            echo "check: $MISSING item(s) missing"
            exit 1
        fi
        echo "check: nothing missing"
    elif [ "$DRY_RUN" = 1 ]; then
        echo "dry-run complete; nothing was changed"
    else
        echo "done; log: $LOG_FILE"
    fi
}

main

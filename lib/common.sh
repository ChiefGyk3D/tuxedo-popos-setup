#!/usr/bin/env bash
# Shared helpers for install.sh and the modules. Sourced, never run.
# shellcheck shell=bash

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "lib/common.sh is sourced by install.sh, not run directly" >&2
    exit 2
fi

# Globals owned by install.sh: MODE, DRY_RUN, MISSING, WORKDIR, APT_DIRTY.

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# step "what": returns 0 when the caller should act. In --dry-run mode it
# prints what would happen and returns 1, so the caller skips the work.
step() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '[dry-run] would: %s\n' "$*"
        return 1
    fi
    info "$*"
}

# report ok|missing "label": one line of --check output; counts what is missing.
report() {
    if [ "$1" = ok ]; then
        printf '  [ok]      %s\n' "$2"
    else
        printf '  [missing] %s\n' "$2"
        MISSING=$((MISSING + 1))
    fi
}

require_root() {
    [ "$(id -u)" = 0 ] || die "run with sudo (or use --check / --dry-run)"
}

resolve_target_user() {
    TARGET_USER=${SUDO_USER:-$(id -un)}
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    [ -n "$TARGET_HOME" ] || die "cannot find a home directory for $TARGET_USER"
}

# as_user cmd...: run as the user who invoked sudo (user-level installs).
as_user() {
    if [ "$(id -u)" = "$(id -u "$TARGET_USER")" ]; then
        env HOME="$TARGET_HOME" "$@"
    else
        runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" "$@"
    fi
}

pkg_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ]
}

# Print the packages from the argument list that are not installed.
pkgs_missing() {
    local p
    for p in "$@"; do
        pkg_installed "$p" || printf '%s\n' "$p"
    done
}

# check_pkgs pkg...: one --check line per package.
check_pkgs() {
    local p
    for p in "$@"; do
        if pkg_installed "$p"; then
            report ok "package $p"
        else
            report missing "package $p"
        fi
    done
}

# apt_install_missing pkg...: install only what is not installed yet.
apt_install_missing() {
    local -a todo
    mapfile -t todo < <(pkgs_missing "$@")
    if [ "${#todo[@]}" -eq 0 ]; then
        info "already installed: $*"
        return 0
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${todo[@]}"
}

apt_refresh() {
    if [ "${APT_DIRTY:-0}" = 1 ]; then
        apt-get update
        APT_DIRTY=0
    fi
}

# write_if_changed dest mode < content: install the file only when it differs.
write_if_changed() {
    local dest=$1 mode=$2 tmp
    tmp=$(mktemp -p "$WORKDIR")
    cat >"$tmp"
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 0
    fi
    install -D -m "$mode" "$tmp" "$dest"
    rm -f "$tmp"
    case $dest in
        /etc/apt/*)
            APT_DIRTY=1
            ;;
    esac
}

fetch() {
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 --max-time 300 -o "$2" "$1"
}

sha256_ok() {
    printf '%s  %s\n' "$2" "$1" | sha256sum -c --status -
}

# key_has_fpr file fingerprint: does the key file carry that fingerprint?
key_has_fpr() {
    local fprs
    fprs=$(gpg --batch --no-tty --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10 }')
    grep -qx "$2" <<<"$fprs"
}

# keyring_prepare out url fingerprint [sha256]: fetch a key over HTTPS, check
# the optional sha256 and the fingerprint, write a binary keyring to "out".
# Nothing is installed until both checks pass.
keyring_prepare() {
    local out=$1 url=$2 fpr=$3 sha=${4:-} raw
    raw=$(mktemp -p "$WORKDIR")
    fetch "$url" "$raw"
    if [ -n "$sha" ]; then
        sha256_ok "$raw" "$sha" || die "checksum mismatch for $url"
    fi
    key_has_fpr "$raw" "$fpr" || die "key from $url does not carry fingerprint $fpr"
    if grep -q -- '-----BEGIN PGP' "$raw"; then
        gpg --batch --no-tty --dearmor <"$raw" >"$out"
    else
        cp "$raw" "$out"
    fi
}

# ver_ge have want: dotted version comparison.
ver_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]
}

check_arch_x86_64() {
    [ "$(uname -m)" = x86_64 ] || die "this step supports x86_64 only (found $(uname -m))"
}

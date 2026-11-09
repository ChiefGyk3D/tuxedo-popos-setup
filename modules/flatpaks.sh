#!/usr/bin/env bash
# Module: Flathub remote and the Flatpak apps listed in FLATPAK_APPS.
# Sourced by install.sh, never run.
# shellcheck shell=bash
#
# The Flathub remote file URL comes from https://flathub.org/setup (fetched
# 2026-11-09). Apps are installed system-wide.

FLATHUB_REPO_URL=https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak_valid_id() {
    [[ $1 =~ ^[A-Za-z0-9_.-]+$ ]]
}

flatpak_has_flathub() {
    flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub
}

mod_flatpaks_check() {
    local app
    for app in "${FLATPAK_APPS[@]}"; do
        flatpak_valid_id "$app" || die "invalid Flatpak app id in config: $app"
    done
    if ! command -v flatpak >/dev/null 2>&1; then
        report missing "flatpak"
        return 0
    fi
    report ok "flatpak"
    if flatpak_has_flathub; then
        report ok "flathub remote"
    else
        report missing "flathub remote (system)"
    fi
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info --system "$app" >/dev/null 2>&1; then
            report ok "flatpak $app"
        else
            report missing "flatpak $app"
        fi
    done
}

mod_flatpaks_apply() {
    local app
    for app in "${FLATPAK_APPS[@]}"; do
        flatpak_valid_id "$app" || die "invalid Flatpak app id in config: $app"
    done
    if step "ensure flatpak is installed"; then
        apt_install_missing flatpak
    fi
    if step "add the flathub remote (system)"; then
        flatpak remote-add --system --if-not-exists flathub "$FLATHUB_REPO_URL"
    fi
    for app in "${FLATPAK_APPS[@]}"; do
        if step "install flatpak $app"; then
            if flatpak info --system "$app" >/dev/null 2>&1; then
                info "already installed: $app"
            else
                flatpak install --system --noninteractive -y flathub "$app"
            fi
        fi
    done
}

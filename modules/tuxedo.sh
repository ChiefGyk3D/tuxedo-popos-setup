#!/usr/bin/env bash
# Module: TUXEDO drivers and Control Center from TUXEDO's signed apt repo.
# Sourced by install.sh, never run.
# shellcheck shell=bash
#
# Why this is scoped so tightly: TUXEDO's repo carries kernels, firmware, GPU
# stacks and Tomte. On Pop!_OS none of those may come from it. The repo is
# pinned to priority 100 (it can add packages Pop lacks, never replace one),
# and those package families are blocked outright at -1.
#
# Tomte is deliberately NOT installed: it treats Pop!_OS as Ubuntu and cannot
# exclude modules.
#
# Where each fact came from (all fetched 2026-11-09):
#   - Repo URI and suite: https://deb.tuxedocomputers.com/ubuntu/dists/noble/
#     (InRelease answered HTTP 200). The vendor help page that documents the
#     repo is JavaScript-gated and could not be fetched, so the URI is
#     UNVERIFIED against a vendor docs page.
#   - Keyring package and its sha256: the vendor's own Packages index at
#     https://deb.tuxedocomputers.com/ubuntu/dists/noble/main/binary-amd64/Packages
#     (package tuxedo-archive-keyring 2024.04.01~tux3). Re-downloaded and
#     re-hashed on the same date; the hash matched.
#   - Fingerprint: read from the key inside that package with
#     gpg --show-keys. No vendor docs page states it, so it is UNVERIFIED
#     against one; trust rests on HTTPS to the vendor plus the pinned hash.
# If the vendor rotates the keyring package the pinned hash fails closed:
# update TUXEDO_KEYRING_DEB_* after checking the new package by hand.

TUXEDO_URI=https://deb.tuxedocomputers.com/ubuntu
TUXEDO_KEYRING_DEB=tuxedo-archive-keyring_2024.04.01~tux3_all.deb
TUXEDO_KEYRING_DEB_URL=$TUXEDO_URI/pool/main/t/tuxedo-archive-keyring/$TUXEDO_KEYRING_DEB
TUXEDO_KEYRING_DEB_SHA256=f9d11dcc2aeac949fa3c1ebe8658e6a1359ca7720a857df9e736c05ab40ad53e
TUXEDO_KEY_FPR=E5D0C320BBCE8D21CDF60DD5120ED28D54840598
TUXEDO_KEYRING=/usr/share/tuxedo-archive-keyring/tuxedo-archive-keyring.gpg
TUXEDO_PREFS=/etc/apt/preferences.d/tuxedo
TUXEDO_SOURCE=/etc/apt/sources.list.d/tuxedo.sources
TUXEDO_PACKAGES=(tuxedo-drivers tuxedo-control-center)

tuxedo_write_prefs() {
    write_if_changed "$TUXEDO_PREFS" 0644 <<'EOF'
# Managed by tuxedo-popos-setup.
# Tuxedo repo: may add Tuxedo-only packages, never replace Pop's.
Package: *
Pin: origin deb.tuxedocomputers.com
Pin-Priority: 100

# Never from Tuxedo on Pop: kernel, firmware (theirs is older), GPU stack, Tomte.
Package: linux-firmware* linux-tuxedo* linux-image-* linux-headers-* linux-modules-* nvidia-* libnvidia-* *nvidia* mesa-* libgl1-mesa* libdrm* tuxedo-tomte* tuxedo-suite tuxedo-fix-* tuxedo-board-*
Pin: origin deb.tuxedocomputers.com
Pin-Priority: -1
EOF
}

tuxedo_write_source() {
    write_if_changed "$TUXEDO_SOURCE" 0644 <<EOF
# Managed by tuxedo-popos-setup.
Types: deb
URIs: $TUXEDO_URI
Suites: noble
Components: main
Enabled: yes
Signed-By: $TUXEDO_KEYRING
EOF
}

mod_tuxedo_check() {
    if grep -qi tuxedo /sys/class/dmi/id/sys_vendor 2>/dev/null; then
        report ok "hardware vendor is TUXEDO"
    else
        warn "DMI vendor does not say TUXEDO; this module is meant for TUXEDO hardware"
    fi
    if [ -f "$TUXEDO_KEYRING" ] && key_has_fpr "$TUXEDO_KEYRING" "$TUXEDO_KEY_FPR"; then
        report ok "TUXEDO keyring present with the expected fingerprint"
    else
        report missing "TUXEDO keyring with fingerprint $TUXEDO_KEY_FPR"
    fi
    if [ -f "$TUXEDO_PREFS" ]; then
        report ok "apt pin file $TUXEDO_PREFS"
    else
        report missing "apt pin file $TUXEDO_PREFS"
    fi
    if [ -f "$TUXEDO_SOURCE" ]; then
        report ok "apt source $TUXEDO_SOURCE"
    else
        report missing "apt source $TUXEDO_SOURCE"
    fi
    check_pkgs "${TUXEDO_PACKAGES[@]}"
    if pkg_installed tuxedo-tomte; then
        report missing "tuxedo-tomte must not be installed on Pop!_OS (remove it)"
    else
        report ok "tuxedo-tomte is not installed"
    fi
}

mod_tuxedo_apply() {
    local deb sim
    if step "install the TUXEDO keyring (sha256 pinned, fingerprint checked)"; then
        deb=$WORKDIR/$TUXEDO_KEYRING_DEB
        fetch "$TUXEDO_KEYRING_DEB_URL" "$deb"
        sha256_ok "$deb" "$TUXEDO_KEYRING_DEB_SHA256" || die "TUXEDO keyring package checksum mismatch, stopping"
        if ! pkg_installed tuxedo-archive-keyring; then
            dpkg -i "$deb"
        fi
        key_has_fpr "$TUXEDO_KEYRING" "$TUXEDO_KEY_FPR" || die "TUXEDO keyring fingerprint mismatch, stopping"
    fi
    # The pin goes in before the source, so nothing is ever pulled unpinned.
    if step "write the apt pin and the scoped apt source"; then
        tuxedo_write_prefs
        tuxedo_write_source
        apt_refresh
    fi
    if step "simulate the install (must not remove any package)"; then
        sim=$(apt-get -s install --no-install-recommends "${TUXEDO_PACKAGES[@]}")
        if grep -q '^Remv' <<<"$sim"; then
            die "the simulated install would REMOVE packages, stopping"
        fi
        grep -E '^Inst' <<<"$sim" || echo "nothing new to install"
    fi
    if step "install ${TUXEDO_PACKAGES[*]}"; then
        apt_install_missing "${TUXEDO_PACKAGES[@]}"
        dkms status | grep -i tuxedo || echo "no tuxedo dkms module listed yet (a reboot may be needed)"
    fi
}
